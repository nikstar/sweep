use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    net::{Ipv4Addr, Ipv6Addr, SocketAddr},
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use anyhow::Context;
use bencode::{BencodeValue, ByteBuf};
use futures_channel::oneshot;
use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, ConnectionOptions, ListenerMode,
    ListenerOptions, ManagedTorrent, MetadataProgress, Session, SessionOptions,
    TrackerCommsTrackerStats, api::TorrentIdOrHash, dht::Id20, generate_azereus_style,
    http_api_types::PeerStatsFilter,
};
use tokio::runtime::{Builder, Runtime};

uniffi::setup_scaffolding!();

#[cfg(test)]
mod tests;

const TRACKER_COMPAT_USER_AGENT: &str = "Transmission/4.0.6";
const TRACKER_COMPAT_TIMEOUT: Duration = Duration::from_secs(12);
const BYTES_PER_MIB: f64 = 1024.0 * 1024.0;

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum SweepError {
    #[error("{0}")]
    Message(String),
}

impl From<anyhow::Error> for SweepError {
    fn from(error: anyhow::Error) -> Self {
        Self::Message(format!("{error:#}"))
    }
}

impl From<oneshot::Canceled> for SweepError {
    fn from(_: oneshot::Canceled) -> Self {
        Self::Message("rqbit task was cancelled before it completed".to_owned())
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentFileSnapshot {
    pub id: u64,
    pub path: String,
    pub length: u64,
    pub progress_bytes: u64,
    pub progress_runs: Vec<TorrentPieceRunSnapshot>,
    pub included: bool,
    pub is_padding: bool,
    pub priority: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentTrackerSnapshot {
    pub id: u64,
    pub url: String,
    pub kind: String,
    pub scrape_url: Option<String>,
    pub status: String,
    pub last_error: Option<String>,
    pub last_announce_unix_seconds: Option<u64>,
    pub next_announce_unix_seconds: Option<u64>,
    pub seeders: Option<u32>,
    pub leechers: Option<u32>,
    pub downloads: Option<u32>,
    pub last_peer_count: Option<u64>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentPieceRunSnapshot {
    pub id: u64,
    pub state: String,
    pub piece_count: u64,
    pub byte_count: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentPeerSnapshot {
    pub id: String,
    pub address: String,
    pub state: String,
    pub connection_kind: Option<String>,
    pub peer_id: Option<String>,
    pub client: Option<String>,
    pub feature_flags: Vec<String>,
    pub country_code: Option<String>,
    pub availability: Option<f64>,
    pub available_pieces: Option<u32>,
    pub downloaded_bytes: u64,
    pub uploaded_bytes: u64,
    pub download_bps: Option<f64>,
    pub upload_bps: Option<f64>,
    pub connection_attempts: u32,
    pub connections: u32,
    pub errors: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TransportSnapshot {
    pub name: String,
    pub attempts: u64,
    pub connected: u64,
    pub failed: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NetworkSnapshot {
    pub dht_nodes_v4: Option<u64>,
    pub dht_nodes_v6: Option<u64>,
    pub dht_outstanding: Option<u64>,
    pub transports: Vec<TransportSnapshot>,
    pub live_tcp: u32,
    pub live_utp: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentSessionSnapshot {
    pub download_bps: f64,
    pub upload_bps: f64,
    pub downloaded_bytes: u64,
    pub uploaded_bytes: u64,
    pub live_peers: u32,
    pub connecting_peers: u32,
    pub queued_peers: u32,
    pub seen_peers: u32,
    pub uptime_seconds: u64,
    pub network: NetworkSnapshot,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentSnapshot {
    pub checked_bytes: Option<u64>,
    pub id: u64,
    pub name: String,
    pub info_hash: String,
    pub state: String,
    pub files: Vec<TorrentFileSnapshot>,
    pub trackers: Vec<TorrentTrackerSnapshot>,
    pub peers: Vec<TorrentPeerSnapshot>,
    pub piece_runs: Vec<TorrentPieceRunSnapshot>,
    pub progress_bytes: u64,
    pub total_bytes: u64,
    pub uploaded_bytes: u64,
    pub download_bps: f64,
    pub upload_bps: f64,
    pub error: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DiscoverySnapshot {
    pub info_hash: String,
    pub is_active: bool,
    pub elapsed_seconds: u64,
    pub peers_found: u64,
    pub peers_tried: u64,
    pub peers_active: u64,
    pub peers_failed: u64,
    pub last_peer_error: Option<String>,
    pub trackers: Vec<TorrentTrackerSnapshot>,
}

struct Discovery {
    progress: MetadataProgress,
    tracker_urls: BTreeSet<String>,
    started: Instant,
    finished: Mutex<Option<Instant>>,
}

#[derive(uniffi::Object)]
pub struct SweepEngine {
    runtime: Runtime,
    session: Arc<Session>,
    peer_id: Id20,
    pending_adds: Mutex<HashMap<String, tokio::task::AbortHandle>>,
    discoveries: Mutex<HashMap<String, Arc<Discovery>>>,
}

impl SweepEngine {
    /// Rust-only configuration hook for controlled diagnostics and integration tests.
    /// The Apple apps use `new` and retain the normal TCP/uTP and discovery defaults.
    pub fn with_session_options(
        download_dir: String,
        mut options: SessionOptions,
    ) -> Result<Arc<Self>, SweepError> {
        let runtime = Builder::new_multi_thread()
            .enable_all()
            .thread_name("sweep-rqbit")
            .build()
            .context("failed to create rqbit runtime")?;
        let peer_id = tracker_compatible_peer_id();
        options.peer_id = Some(peer_id);
        let session = runtime
            .block_on(Session::new_with_opts(PathBuf::from(download_dir), options))
            .context("failed to create rqbit session")?;

        Ok(Arc::new(Self {
            runtime,
            session,
            peer_id,
            pending_adds: Mutex::new(HashMap::new()),
            discoveries: Mutex::new(HashMap::new()),
        }))
    }
}

#[uniffi::export]
impl SweepEngine {
    #[uniffi::constructor]
    pub fn new(download_dir: String) -> Result<Arc<Self>, SweepError> {
        Self::with_session_options(
            download_dir,
            SessionOptions {
                disable_dht_persistence: true,
                listen: Some(ListenerOptions {
                    mode: ListenerMode::TcpAndUtp,
                    ..Default::default()
                }),
                connect: Some(ConnectionOptions::default()),
                ..Default::default()
            },
        )
    }

    pub async fn add_magnet(
        &self,
        magnet: String,
        download_dir: String,
        start_paused: bool,
    ) -> Result<TorrentSnapshot, SweepError> {
        let parsed = librqbit::Magnet::parse(&magnet)?;
        let info_hash = parsed
            .as_id20()
            .context("magnet link did not contain a v1 info hash")?
            .as_string();
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();
        let discovery = Arc::new(Discovery {
            progress: MetadataProgress::default(),
            tracker_urls: parsed
                .trackers
                .into_iter()
                .map(|url| {
                    reqwest::Url::parse(&url)
                        .map(|url| url.to_string())
                        .unwrap_or(url)
                })
                .collect(),
            started: Instant::now(),
            finished: Mutex::new(None),
        });
        self.discoveries
            .lock()
            .unwrap()
            .insert(info_hash.clone(), discovery.clone());
        let task_discovery = discovery.clone();

        let task = runtime.spawn(async move {
            let result = tokio::time::timeout(
                Duration::from_secs(90),
                add_torrent_with_progress(
                    session,
                    AddTorrent::from_url(magnet),
                    download_dir,
                    start_paused,
                    Vec::new(),
                    Some(task_discovery.progress.clone()),
                ),
            )
            .await
            .unwrap_or_else(|_| Err(SweepError::Message(
                "No torrent metadata received after 90 seconds. Peers may be unreachable or incompatible.".to_owned(),
            )));
            *task_discovery.finished.lock().unwrap() = Some(Instant::now());
            let _ = tx.send(result);
        });
        let abort = task.abort_handle();
        if let Some(previous) = self
            .pending_adds
            .lock()
            .unwrap()
            .insert(info_hash.clone(), abort.clone())
        {
            previous.abort();
        }
        let result = rx.await;
        let mut pending = self.pending_adds.lock().unwrap();
        if pending
            .get(&info_hash)
            .is_some_and(|current| current.id() == abort.id())
        {
            pending.remove(&info_hash);
        }
        // Keep failed discovery evidence for the inspector until retry/cancel.
        if matches!(&result, Ok(Ok(_))) {
            let mut discoveries = self.discoveries.lock().unwrap();
            if discoveries
                .get(&info_hash)
                .is_some_and(|current| Arc::ptr_eq(current, &discovery))
            {
                discoveries.remove(&info_hash);
            }
        }
        result?
    }

    pub fn cancel_pending_add(&self, id: String) {
        let id = id.to_ascii_lowercase();
        if let Some(task) = self.pending_adds.lock().unwrap().remove(&id) {
            task.abort();
        }
        self.discoveries.lock().unwrap().remove(&id);
    }

    pub fn discovery_snapshots(&self) -> Vec<DiscoverySnapshot> {
        self.discoveries
            .lock()
            .unwrap()
            .iter()
            .map(|(id, discovery)| {
                let stats = discovery.progress.snapshot();
                let finished = *discovery.finished.lock().unwrap();
                let tracker_stats = discovery
                    .progress
                    .trackers
                    .snapshot()
                    .into_iter()
                    .map(|stats| (stats.url.clone(), stats))
                    .collect::<BTreeMap<_, _>>();
                let mut urls = discovery.tracker_urls.clone();
                urls.extend(tracker_stats.keys().cloned());
                let trackers = urls
                    .into_iter()
                    .enumerate()
                    .map(|(index, url)| {
                        let stats = tracker_stats.get(&url);
                        snapshot_tracker(index, url, stats)
                    })
                    .collect();
                DiscoverySnapshot {
                    info_hash: id.clone(),
                    is_active: finished.is_none(),
                    elapsed_seconds: finished
                        .unwrap_or_else(Instant::now)
                        .duration_since(discovery.started)
                        .as_secs(),
                    peers_found: stats.discovered,
                    peers_tried: stats.attempted,
                    peers_active: if finished.is_none() { stats.active } else { 0 },
                    peers_failed: stats.failed,
                    last_peer_error: stats.last_error,
                    trackers,
                }
            })
            .collect()
    }

    pub fn torrent_file(&self, id: String) -> Result<Vec<u8>, SweepError> {
        let handle = self
            .session
            .get(parse_torrent_id(&id)?)
            .context("torrent is not in the engine")?;
        Ok(handle.with_metadata(|metadata| metadata.torrent_bytes.to_vec())?)
    }

    pub async fn add_torrent_file(
        &self,
        torrent_bytes: Vec<u8>,
        download_dir: String,
        start_paused: bool,
    ) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let peer_id = self.peer_id;
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let initial_peers = if start_paused {
                Vec::new()
            } else {
                announce_initial_peers_for_torrent(&torrent_bytes, peer_id, session.announce_port())
                    .await
            };
            let result = add_torrent_to_session(
                session,
                AddTorrent::from_bytes(torrent_bytes),
                download_dir,
                start_paused,
                initial_peers,
            )
            .await;
            let _ = tx.send(result);
        });

        rx.await?
    }

    pub async fn list_torrents(&self) -> Result<Vec<TorrentSnapshot>, SweepError> {
        let handles = self.session.with_torrents(|torrents| {
            torrents
                .map(|(_, handle)| handle.clone())
                .collect::<Vec<_>>()
        });
        Ok(handles.iter().map(snapshot).collect())
    }

    pub async fn session_snapshot(&self) -> Result<TorrentSessionSnapshot, SweepError> {
        Ok(snapshot_session(&self.session))
    }

    pub async fn pause_torrent(&self, id: String) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = pause_torrent_in_session(session, id).await;
            let _ = tx.send(result);
        });

        rx.await?
    }

    pub async fn resume_torrent(&self, id: String) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = resume_torrent_in_session(session, id).await;
            let _ = tx.send(result);
        });

        rx.await?
    }

    pub async fn remove_torrent(&self, id: String, delete_data: bool) -> Result<(), SweepError> {
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = remove_torrent_from_session(session, id, delete_data).await;
            let _ = tx.send(result);
        });

        rx.await?
    }

    pub async fn update_only_files(
        &self,
        id: String,
        file_ids: Vec<u64>,
    ) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = update_only_files_in_session(session, id, file_ids).await;
            let _ = tx.send(result);
        });

        rx.await?
    }
}

async fn add_torrent_to_session(
    session: Arc<Session>,
    add_torrent: AddTorrent<'static>,
    download_dir: String,
    start_paused: bool,
    initial_peers: Vec<SocketAddr>,
) -> Result<TorrentSnapshot, SweepError> {
    add_torrent_with_progress(
        session,
        add_torrent,
        download_dir,
        start_paused,
        initial_peers,
        None,
    )
    .await
}

async fn add_torrent_with_progress(
    session: Arc<Session>,
    add_torrent: AddTorrent<'static>,
    download_dir: String,
    start_paused: bool,
    initial_peers: Vec<SocketAddr>,
    metadata_progress: Option<MetadataProgress>,
) -> Result<TorrentSnapshot, SweepError> {
    let response = session
        .add_torrent(
            add_torrent,
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(download_dir),
                paused: start_paused,
                initial_peers: (!initial_peers.is_empty()).then_some(initial_peers),
                metadata_progress,
                ..Default::default()
            }),
        )
        .await?;

    let handle = match response {
        AddTorrentResponse::Added(_, handle) => handle,
        AddTorrentResponse::AlreadyManaged(_, handle) => handle,
        AddTorrentResponse::ListOnly(_) => {
            return Err(SweepError::Message(
                "list-only responses are not used by Sweep".to_owned(),
            ));
        }
    };

    Ok(snapshot(&handle))
}

fn tracker_compatible_peer_id() -> Id20 {
    generate_azereus_style(*b"rQ", (9, 0, 0, 0))
}

async fn announce_initial_peers_for_torrent(
    torrent_bytes: &[u8],
    peer_id: Id20,
    announce_port: Option<u16>,
) -> Vec<SocketAddr> {
    let Some(announce_port) = announce_port else {
        return Vec::new();
    };

    let Ok(torrent) = librqbit::torrent_from_bytes(torrent_bytes) else {
        return Vec::new();
    };

    let left = torrent
        .info
        .data
        .length
        .or_else(|| {
            torrent.info.data.files.as_ref().map(|files| {
                files
                    .iter()
                    .map(|file| file.length)
                    .fold(0_u64, u64::saturating_add)
            })
        })
        .unwrap_or_default();

    let trackers = torrent
        .iter_announce()
        .filter_map(|tracker| std::str::from_utf8(tracker.as_ref()).ok())
        .filter(|tracker| tracker.starts_with("http://") || tracker.starts_with("https://"))
        .collect::<Vec<_>>();
    if trackers.is_empty() {
        return Vec::new();
    }

    let Ok(client) = reqwest::Client::builder()
        .timeout(TRACKER_COMPAT_TIMEOUT)
        .build()
    else {
        return Vec::new();
    };

    let mut peers = Vec::new();
    for tracker in trackers {
        if let Ok(mut tracker_peers) = announce_initial_peers(
            &client,
            tracker,
            torrent.info_hash,
            peer_id,
            announce_port,
            left,
        )
        .await
        {
            peers.append(&mut tracker_peers);
        }
    }
    peers.sort_unstable();
    peers.dedup();
    peers
}

async fn announce_initial_peers(
    client: &reqwest::Client,
    tracker: &str,
    info_hash: Id20,
    peer_id: Id20,
    announce_port: u16,
    left: u64,
) -> anyhow::Result<Vec<SocketAddr>> {
    let mut url = reqwest::Url::parse(tracker)?;
    let key = u32::from_be_bytes(peer_id.0[8..12].try_into()?);
    let mut query = format!(
        "info_hash={}&peer_id={}&port={announce_port}&uploaded=0&downloaded=0&left={left}&numwant=80&key={key:08X}&compact=1&supportcrypto=0&event=started",
        urlencoding::encode_binary(&info_hash.0),
        urlencoding::encode_binary(&peer_id.0)
    );
    if let Some(existing_query) = url.query() {
        query.push('&');
        query.push_str(existing_query);
    }
    url.set_query(Some(&query));

    let response = client
        .get(url)
        .header(reqwest::header::USER_AGENT, TRACKER_COMPAT_USER_AGENT)
        .send()
        .await?;
    if !response.status().is_success() {
        anyhow::bail!("tracker responded with {}", response.status());
    }

    let bytes = response.bytes().await?;
    parse_compact_tracker_peers(&bytes)
}

fn parse_compact_tracker_peers(bytes: &[u8]) -> anyhow::Result<Vec<SocketAddr>> {
    let value = bencode::dyn_from_bytes::<ByteBuf<'_>>(bytes)
        .map_err(|error| anyhow::anyhow!("{error:#}"))?;
    let BencodeValue::Dict(dict) = value else {
        return Ok(Vec::new());
    };

    if let Some(BencodeValue::Bytes(reason)) = dict.get(&ByteBuf(b"failure reason")) {
        anyhow::bail!("tracker returned failure: {reason}");
    }

    let mut peers = Vec::new();
    if let Some(BencodeValue::Bytes(compact_peers)) = dict.get(&ByteBuf(b"peers")) {
        peers.extend(parse_compact_ipv4_peers(compact_peers.as_ref()));
    }
    if let Some(BencodeValue::Bytes(compact_peers6)) = dict.get(&ByteBuf(b"peers6")) {
        peers.extend(parse_compact_ipv6_peers(compact_peers6.as_ref()));
    }
    Ok(peers)
}

fn parse_compact_ipv4_peers(bytes: &[u8]) -> Vec<SocketAddr> {
    bytes
        .chunks_exact(6)
        .map(|chunk| {
            SocketAddr::new(
                Ipv4Addr::new(chunk[0], chunk[1], chunk[2], chunk[3]).into(),
                u16::from_be_bytes([chunk[4], chunk[5]]),
            )
        })
        .collect()
}

fn parse_compact_ipv6_peers(bytes: &[u8]) -> Vec<SocketAddr> {
    bytes
        .chunks_exact(18)
        .map(|chunk| {
            let mut addr = [0_u8; 16];
            addr.copy_from_slice(&chunk[..16]);
            SocketAddr::new(
                Ipv6Addr::from(addr).into(),
                u16::from_be_bytes([chunk[16], chunk[17]]),
            )
        })
        .collect()
}

async fn pause_torrent_in_session(
    session: Arc<Session>,
    id: String,
) -> Result<TorrentSnapshot, SweepError> {
    let id = parse_torrent_id(&id)?;
    let handle = session
        .get(id)
        .with_context(|| format!("torrent {id} is not managed"))?;
    if !handle.is_paused() {
        session.pause(&handle).await?;
    }
    Ok(snapshot(&handle))
}

async fn resume_torrent_in_session(
    session: Arc<Session>,
    id: String,
) -> Result<TorrentSnapshot, SweepError> {
    let id = parse_torrent_id(&id)?;
    let handle = session
        .get(id)
        .with_context(|| format!("torrent {id} is not managed"))?;
    // Starting again during the initial check spawns a second initializer in
    // rqbit. The first can win with start_paused=true while the second changes
    // the intent flag to false, leaving an unresumable paused handle.
    handle.wait_until_initialized().await?;
    if handle.is_paused() {
        session.unpause(&handle).await?;
    }
    Ok(snapshot(&handle))
}

async fn remove_torrent_from_session(
    session: Arc<Session>,
    id: String,
    delete_data: bool,
) -> Result<(), SweepError> {
    let id = parse_torrent_id(&id)?;
    if session.get(id).is_none() {
        return Ok(());
    }
    session.delete(id, delete_data).await?;
    Ok(())
}

async fn update_only_files_in_session(
    session: Arc<Session>,
    id: String,
    file_ids: Vec<u64>,
) -> Result<TorrentSnapshot, SweepError> {
    let id = parse_torrent_id(&id)?;
    let handle = session
        .get(id)
        .with_context(|| format!("torrent {id} is not managed"))?;
    let only_files = file_ids
        .into_iter()
        .map(|file_id| {
            usize::try_from(file_id).map_err(|_| {
                SweepError::Message(format!("file id {file_id} is too large for this platform"))
            })
        })
        .collect::<Result<HashSet<_>, _>>()?;

    // Restored selections must be applied after the check, while still paused.
    handle.wait_until_initialized().await?;
    session.update_only_files(&handle, &only_files).await?;
    Ok(snapshot(&handle))
}

fn parse_torrent_id(id: &str) -> Result<TorrentIdOrHash, SweepError> {
    TorrentIdOrHash::parse(id).map_err(|error| {
        SweepError::Message(format!(
            "torrent id must be a rqbit id or 40-character info hash: {error:#}"
        ))
    })
}

fn snapshot(handle: &Arc<ManagedTorrent>) -> TorrentSnapshot {
    let stats = handle.stats();
    let files = snapshot_files(handle, &stats.file_progress);
    let trackers = snapshot_trackers(handle);
    let peers = snapshot_peers(handle);
    let piece_runs = snapshot_piece_runs(handle);
    let (download_bps, upload_bps) = stats
        .live
        .as_ref()
        .map(|live| {
            (
                live.download_speed.mbps * BYTES_PER_MIB,
                live.upload_speed.mbps * BYTES_PER_MIB,
            )
        })
        .unwrap_or_default();

    TorrentSnapshot {
        checked_bytes: (stats.state.to_string() == "initializing").then_some(stats.progress_bytes),
        id: handle.id() as u64,
        name: handle
            .name()
            .unwrap_or_else(|| handle.info_hash().as_string()),
        info_hash: handle.info_hash().as_string(),
        state: stats.state.to_string(),
        files,
        trackers,
        peers,
        piece_runs,
        progress_bytes: if stats.state.to_string() == "initializing" {
            0
        } else {
            stats.progress_bytes
        },
        total_bytes: stats.total_bytes,
        uploaded_bytes: stats.uploaded_bytes,
        download_bps,
        upload_bps,
        error: stats.error,
    }
}

fn snapshot_trackers(handle: &Arc<ManagedTorrent>) -> Vec<TorrentTrackerSnapshot> {
    let tracker_stats = handle
        .tracker_stats_snapshot()
        .into_iter()
        .map(|stats| (stats.url.clone(), stats))
        .collect::<BTreeMap<_, _>>();
    let mut tracker_urls = handle
        .shared()
        .trackers
        .iter()
        .map(|url| url.to_string())
        .collect::<BTreeSet<_>>();
    tracker_urls.extend(tracker_stats.keys().cloned());

    tracker_urls
        .into_iter()
        .enumerate()
        .map(|(idx, url)| {
            let stats = tracker_stats.get(&url);
            snapshot_tracker(idx, url, stats)
        })
        .collect()
}

fn snapshot_tracker(
    idx: usize,
    url: String,
    stats: Option<&TrackerCommsTrackerStats>,
) -> TorrentTrackerSnapshot {
    let kind = stats
        .map(|stats| stats.kind.clone())
        .or_else(|| {
            reqwest::Url::parse(&url)
                .ok()
                .map(|url| url.scheme().to_ascii_uppercase())
        })
        .unwrap_or_else(|| "Unknown".to_owned());

    TorrentTrackerSnapshot {
        id: idx as u64,
        scrape_url: scrape_url_for_tracker(&url),
        url,
        kind,
        status: stats
            .map(|stats| stats.status.clone())
            .unwrap_or_else(|| "Configured".to_owned()),
        last_error: stats.and_then(|stats| stats.last_error.clone()),
        last_announce_unix_seconds: stats.and_then(|stats| stats.last_announce_unix_seconds),
        next_announce_unix_seconds: stats.and_then(|stats| stats.next_announce_unix_seconds),
        seeders: stats.and_then(|stats| u64_to_u32(stats.seeders)),
        leechers: stats.and_then(|stats| u64_to_u32(stats.leechers)),
        downloads: stats.and_then(|stats| u64_to_u32(stats.downloads)),
        last_peer_count: stats.and_then(|stats| stats.last_peer_count),
    }
}

fn scrape_url_for_tracker(url: &str) -> Option<String> {
    let mut url = reqwest::Url::parse(url).ok()?;
    let path = url.path();
    if !path.ends_with("/announce") {
        return None;
    }
    let scrape_path = format!("{}{}", &path[..path.len() - "/announce".len()], "/scrape");
    url.set_path(&scrape_path);
    Some(url.to_string())
}

fn snapshot_peers(handle: &Arc<ManagedTorrent>) -> Vec<TorrentPeerSnapshot> {
    let Some(live) = handle.live() else {
        return Vec::new();
    };
    let total_pieces = handle
        .with_metadata(|metadata| metadata.lengths().total_pieces())
        .ok()
        .filter(|pieces| *pieces > 0);

    let mut peers = live
        .per_peer_stats_snapshot(PeerStatsFilter::default())
        .peers
        .into_iter()
        .map(|(address, peer)| {
            let availability = peer.available_pieces.and_then(|available| {
                total_pieces.map(|total| {
                    let available = available.min(total);
                    f64::from(available) / f64::from(total)
                })
            });

            TorrentPeerSnapshot {
                id: address.clone(),
                address,
                state: peer.state.to_owned(),
                connection_kind: peer.conn_kind.map(|kind| kind.to_string()),
                peer_id: peer.peer_id,
                client: peer.client,
                feature_flags: peer.feature_flags,
                country_code: None,
                availability,
                available_pieces: peer.available_pieces,
                downloaded_bytes: peer.counters.fetched_bytes,
                uploaded_bytes: peer.counters.uploaded_bytes,
                download_bps: None,
                upload_bps: None,
                connection_attempts: peer.counters.connection_attempts,
                connections: peer.counters.connections,
                errors: peer.counters.errors,
            }
        })
        .collect::<Vec<_>>();
    peers.sort_by(|lhs, rhs| lhs.address.cmp(&rhs.address));
    peers
}

fn u64_to_u32(value: Option<u64>) -> Option<u32> {
    value.map(|value| value.min(u64::from(u32::MAX)) as u32)
}

fn snapshot_files(handle: &Arc<ManagedTorrent>, file_progress: &[u64]) -> Vec<TorrentFileSnapshot> {
    let only_files = handle.only_files();
    handle
        .with_metadata(|metadata| {
            metadata
                .file_infos
                .iter()
                .enumerate()
                .map(|(idx, file)| {
                    let included = only_files
                        .as_ref()
                        .map(|files| files.contains(&idx))
                        .unwrap_or(true);
                    let progress_bytes = file_progress.get(idx).copied().unwrap_or_default();
                    TorrentFileSnapshot {
                        id: idx as u64,
                        path: file.relative_filename.to_string_lossy().into_owned(),
                        length: file.len,
                        progress_bytes,
                        progress_runs: progress_runs(progress_bytes, file.len, included),
                        included,
                        is_padding: file.attrs.padding,
                        priority: if included { "normal" } else { "skip" }.to_owned(),
                    }
                })
                .collect()
        })
        .unwrap_or_default()
}

fn snapshot_piece_runs(handle: &Arc<ManagedTorrent>) -> Vec<TorrentPieceRunSnapshot> {
    let pieces = handle.piece_snapshot();
    let mut runs = Vec::<TorrentPieceRunSnapshot>::new();

    for piece in pieces {
        let state = piece.status.as_str();
        if let Some(last) = runs.last_mut()
            && last.state == state
        {
            last.piece_count += 1;
            last.byte_count += u64::from(piece.length);
            continue;
        }

        runs.push(TorrentPieceRunSnapshot {
            id: runs.len() as u64,
            state: state.to_owned(),
            piece_count: 1,
            byte_count: u64::from(piece.length),
        });
    }

    runs
}

fn progress_runs(
    progress_bytes: u64,
    total_bytes: u64,
    included: bool,
) -> Vec<TorrentPieceRunSnapshot> {
    if total_bytes == 0 {
        return Vec::new();
    }

    let progress_bytes = progress_bytes.min(total_bytes);
    let mut runs = Vec::new();
    if progress_bytes > 0 {
        runs.push(TorrentPieceRunSnapshot {
            id: 0,
            state: "downloaded".to_owned(),
            piece_count: 1,
            byte_count: progress_bytes,
        });
    }

    let remaining_bytes = total_bytes - progress_bytes;
    if remaining_bytes > 0 {
        runs.push(TorrentPieceRunSnapshot {
            id: runs.len() as u64,
            state: if included { "needed" } else { "skipped" }.to_owned(),
            piece_count: 1,
            byte_count: remaining_bytes,
        });
    }

    runs
}

fn snapshot_session(session: &Arc<Session>) -> TorrentSessionSnapshot {
    let stats = session.stats_snapshot();
    let dht = session.get_dht().map(|dht| dht.stats());
    TorrentSessionSnapshot {
        download_bps: stats.download_speed.mbps * BYTES_PER_MIB,
        upload_bps: stats.upload_speed.mbps * BYTES_PER_MIB,
        downloaded_bytes: stats.counters.fetched_bytes,
        uploaded_bytes: stats.counters.uploaded_bytes,
        live_peers: stats.peers.live,
        connecting_peers: stats.peers.connecting,
        queued_peers: stats.peers.queued,
        seen_peers: stats.peers.seen,
        uptime_seconds: stats.uptime_seconds,
        network: NetworkSnapshot {
            dht_nodes_v4: dht.as_ref().map(|s| s.routing_table_size as u64),
            dht_nodes_v6: dht.as_ref().map(|s| s.routing_table_size_v6 as u64),
            dht_outstanding: dht.as_ref().map(|s| s.outstanding_requests as u64),
            transports: [
                ("TCP IPv4", &stats.connections.tcp.v4),
                ("TCP IPv6", &stats.connections.tcp.v6),
                ("uTP IPv4", &stats.connections.utp.v4),
                ("uTP IPv6", &stats.connections.utp.v6),
            ]
            .into_iter()
            .map(|(name, counters)| TransportSnapshot {
                name: name.to_owned(),
                attempts: counters.attempts,
                connected: counters.successes,
                failed: counters.errors,
            })
            .collect(),
            live_tcp: stats.peers.live_tcp,
            live_utp: stats.peers.live_utp,
        },
    }
}
