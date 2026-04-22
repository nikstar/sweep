use std::{env, fs, path::PathBuf, time::Duration};

use sweep_rqbit::SweepEngine;
use tokio::runtime::Builder;

fn main() -> anyhow::Result<()> {
    let args = env::args().collect::<Vec<_>>();
    let [_, torrent_path, output_dir, min_bytes, max_seconds] = args.as_slice() else {
        anyhow::bail!(
            "usage: live_probe <torrent-path> <output-dir> <min-progress-bytes> <max-seconds>"
        );
    };

    let min_bytes = min_bytes.parse::<u64>()?;
    let max_seconds = max_seconds.parse::<u64>()?;
    fs::create_dir_all(output_dir)?;

    let engine = SweepEngine::new(output_dir.to_owned())?;
    let torrent_bytes = fs::read(PathBuf::from(torrent_path))?;
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
    let added = engine
        .add_torrent_file(torrent_bytes, output_dir, false)
        .await?;
    println!(
        "added {} {} total={} progress={}",
        added.id, added.name, added.total_bytes, added.progress_bytes
    );

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
        if torrent.state != "initializing" && torrent.progress_bytes >= min_bytes
            || (torrent.total_bytes > 0 && torrent.progress_bytes >= torrent.total_bytes)
        {
            return Ok(());
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }

    anyhow::bail!("download did not reach {min_bytes} bytes in {max_seconds}s")
}
