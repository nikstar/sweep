use std::{env, fs, path::PathBuf, time::Duration};

use librqbit::{ConnectionOptions, ListenerMode, ListenerOptions, SessionOptions};
use sweep_rqbit::SweepEngine;
use tokio::runtime::Builder;

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "warn".into()),
        )
        .with_writer(std::io::stderr)
        .init();
    let args = env::args().collect::<Vec<_>>();
    let [_, torrent_path, output_dir, min_bytes, max_seconds] = args.as_slice() else {
        anyhow::bail!(
            "usage: live_probe <torrent-or-magnet-file> <output-dir> <min-progress-bytes> <max-seconds>"
        );
    };

    let min_bytes = min_bytes.parse::<u64>()?;
    let max_seconds = max_seconds.parse::<u64>()?;
    anyhow::ensure!(
        min_bytes > 0 && max_seconds > 0,
        "byte and time limits must be positive"
    );
    fs::create_dir_all(output_dir)?;

    let transport = env::var("SWEEP_PROBE_TRANSPORT").unwrap_or_else(|_| "both".into());
    let discovery = env::var("SWEEP_PROBE_DISCOVERY").unwrap_or_else(|_| "both".into());
    let mode = match transport.as_str() {
        "both" => ListenerMode::TcpAndUtp,
        "tcp" => ListenerMode::TcpOnly,
        "utp" => ListenerMode::UtpOnly,
        _ => anyhow::bail!("SWEEP_PROBE_TRANSPORT must be both, tcp, or utp"),
    };
    anyhow::ensure!(
        ["both", "dht", "trackers"].contains(&discovery.as_str()),
        "SWEEP_PROBE_DISCOVERY must be both, dht, or trackers"
    );
    let torrent_bytes = fs::read(PathBuf::from(torrent_path))?;
    anyhow::ensure!(
        discovery == "both"
            || std::str::from_utf8(&torrent_bytes)
                .is_ok_and(|value| value.trim().starts_with("magnet:")),
        "isolated discovery tests require a magnet text file"
    );
    println!("probe transport={transport} discovery={discovery}");
    let engine = SweepEngine::with_session_options(
        output_dir.to_owned(),
        SessionOptions {
            disable_dht_persistence: true,
            disable_dht: discovery == "trackers",
            disable_trackers: discovery == "dht",
            disable_local_service_discovery: true,
            listen: Some(ListenerOptions {
                mode,
                ..Default::default()
            }),
            connect: Some(ConnectionOptions {
                enable_tcp: transport != "utp",
                ..Default::default()
            }),
            ..Default::default()
        },
    )?;
    let runtime = Builder::new_current_thread().enable_all().build()?;
    let result = runtime.block_on(async_main(
        engine.clone(),
        torrent_bytes,
        output_dir.to_owned(),
        min_bytes,
        max_seconds,
    ));
    drop(runtime);
    drop(engine);
    result
}

async fn async_main(
    engine: std::sync::Arc<SweepEngine>,
    torrent_bytes: Vec<u8>,
    output_dir: String,
    min_bytes: u64,
    max_seconds: u64,
) -> anyhow::Result<()> {
    let start_paused = std::env::var_os("SWEEP_PROBE_START_PAUSED").is_some();
    let adding = async {
        if let Ok(magnet) = std::str::from_utf8(&torrent_bytes)
            && magnet.trim().starts_with("magnet:")
        {
            engine
                .add_magnet(magnet.trim().to_owned(), output_dir, start_paused)
                .await
        } else {
            engine
                .add_torrent_file(torrent_bytes, output_dir, start_paused)
                .await
        }
    };
    tokio::pin!(adding);
    let added = tokio::time::timeout(Duration::from_secs(max_seconds), async {
        loop {
            tokio::select! {
                result = &mut adding => break result,
                _ = tokio::time::sleep(Duration::from_secs(2)) => {
                    print_network(&engine).await?;
                    for discovery in engine.discovery_snapshots() {
                        println!("discovery t={}s found={} tried={} active={} failed={} trackers_working={} trackers_failed={} last_peer_error={:?}",
                            discovery.elapsed_seconds, discovery.peers_found, discovery.peers_tried,
                            discovery.peers_active, discovery.peers_failed,
                            discovery.trackers.iter().filter(|t| t.status == "Working").count(),
                            discovery.trackers.iter().filter(|t| t.status == "Error").count(),
                            discovery.last_peer_error);
                    }
                }
            }
        }
    })
    .await
    .map_err(|_| anyhow::anyhow!("metadata discovery did not finish in {max_seconds}s"))??;
    println!(
        "added {} {} total={} progress={}",
        added.id, added.name, added.total_bytes, added.progress_bytes
    );

    if start_paused {
        tokio::time::timeout(
            Duration::from_secs(max_seconds),
            engine.resume_torrent(added.info_hash.clone()),
        )
        .await??;
        println!("resumed after checking files");
    }
    let mut last_progress = None;
    let mut last_peers = None;
    for second in 0..=max_seconds {
        let torrents = engine.list_torrents().await?;
        let torrent = torrents
            .iter()
            .find(|torrent| torrent.id == added.id)
            .or_else(|| torrents.first())
            .ok_or_else(|| anyhow::anyhow!("torrent disappeared"))?;
        let peers = torrent.peers.len();
        let should_print = second <= 5
            || second % 10 == 0
            || last_progress != Some(torrent.progress_bytes)
            || last_peers != Some(peers);
        if should_print {
            print_network(&engine).await?;
            println!(
                "t={second}s state={} progress={}/{} down_bps={} peers={}",
                torrent.state,
                torrent.progress_bytes,
                torrent.total_bytes,
                torrent.download_bps,
                peers
            );
        }
        last_progress = Some(torrent.progress_bytes);
        last_peers = Some(peers);
        if let Some(error) = &torrent.error {
            anyhow::bail!("torrent failed: {error}");
        }
        if torrent.state == "live"
            && (torrent.progress_bytes >= min_bytes
                || (torrent.total_bytes > 0 && torrent.progress_bytes >= torrent.total_bytes))
        {
            return Ok(());
        }
        if second == max_seconds {
            for tracker in &torrent.trackers {
                eprintln!(
                    "tracker={} status={} peers={:?} error={:?}",
                    tracker.url, tracker.status, tracker.last_peer_count, tracker.last_error
                );
            }
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }

    anyhow::bail!("download did not reach {min_bytes} bytes in {max_seconds}s")
}

async fn print_network(engine: &SweepEngine) -> anyhow::Result<()> {
    let network = engine.session_snapshot().await?.network;
    println!(
        "network DHT_nodes_v4={:?} DHT_nodes_v6={:?} DHT_inflight={:?} live_tcp={} live_utp={}",
        network.dht_nodes_v4,
        network.dht_nodes_v6,
        network.dht_outstanding,
        network.live_tcp,
        network.live_utp
    );
    for transport in network.transports {
        println!(
            "transport={} attempted={} connected={} failed={}",
            transport.name, transport.attempts, transport.connected, transport.failed
        );
    }
    Ok(())
}
