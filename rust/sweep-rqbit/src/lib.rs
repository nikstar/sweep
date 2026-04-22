use std::{
    net::{Ipv4Addr, Ipv6Addr, SocketAddr},
    path::PathBuf,
    sync::Arc,
    time::Duration,
};

use anyhow::Context;
use bencode::{BencodeValue, ByteBuf};
use futures_channel::oneshot;
use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, ConnectionOptions, ListenerMode,
    ListenerOptions, ManagedTorrent, Session, SessionOptions, api::TorrentIdOrHash, dht::Id20,
    generate_azereus_style, http_api_types::PeerStatsFilter,
};
use tokio::runtime::{Builder, Runtime};

uniffi::setup_scaffolding!();

const TRACKER_COMPAT_USER_AGENT: &str = "Transmission/4.0.6";
const TRACKER_COMPAT_TIMEOUT: Duration = Duration::from_secs(12);

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
    pub included: bool,
    pub is_padding: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentTrackerSnapshot {
    pub id: u64,
    pub url: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentPeerSnapshot {
    pub id: String,
    pub address: String,
    pub state: String,
    pub connection_kind: Option<String>,
    pub downloaded_bytes: u64,
    pub uploaded_bytes: u64,
    pub connection_attempts: u32,
    pub connections: u32,
    pub errors: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TorrentSnapshot {
    pub id: u64,
    pub name: String,
    pub info_hash: String,
    pub state: String,
    pub files: Vec<TorrentFileSnapshot>,
    pub trackers: Vec<TorrentTrackerSnapshot>,
    pub peers: Vec<TorrentPeerSnapshot>,
    pub progress_bytes: u64,
    pub total_bytes: u64,
    pub uploaded_bytes: u64,
    pub download_bps: f64,
    pub upload_bps: f64,
    pub error: Option<String>,
}

#[derive(uniffi::Object)]
pub struct SweepEngine {
    runtime: Runtime,
    session: Arc<Session>,
    peer_id: Id20,
}

#[uniffi::export]
impl SweepEngine {
    #[uniffi::constructor]
    pub fn new(download_dir: String) -> Result<Arc<Self>, SweepError> {
        let runtime = Builder::new_multi_thread()
            .enable_all()
            .thread_name("sweep-rqbit")
            .build()
            .context("failed to create rqbit runtime")?;
        let peer_id = tracker_compatible_peer_id();
        let session = runtime
            .block_on(Session::new_with_opts(
                PathBuf::from(download_dir),
                SessionOptions {
                    disable_dht_persistence: true,
                    peer_id: Some(peer_id),
                    listen: Some(ListenerOptions {
                        mode: ListenerMode::TcpAndUtp,
                        ..Default::default()
                    }),
                    connect: Some(ConnectionOptions::default()),
                    ..Default::default()
                },
            ))
            .context("failed to create rqbit session")?;

        Ok(Arc::new(Self {
            runtime,
            session,
            peer_id,
        }))
    }

    pub async fn add_magnet(
        &self,
        magnet: String,
        download_dir: String,
        start_paused: bool,
    ) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = add_torrent_to_session(
                session,
                AddTorrent::from_url(magnet),
                download_dir,
                start_paused,
                Vec::new(),
            )
            .await;
            let _ = tx.send(result);
        });

        rx.await?
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
            let initial_peers = announce_initial_peers_for_torrent(
                &torrent_bytes,
                peer_id,
                session.announce_port(),
            )
            .await;
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
}

async fn add_torrent_to_session(
    session: Arc<Session>,
    add_torrent: AddTorrent<'static>,
    download_dir: String,
    start_paused: bool,
    initial_peers: Vec<SocketAddr>,
) -> Result<TorrentSnapshot, SweepError> {
    let response = session
        .add_torrent(
            add_torrent,
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(download_dir),
                paused: start_paused,
                initial_peers: (!initial_peers.is_empty()).then_some(initial_peers),
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
        "info_hash={}&peer_id={}&port={announce_port}&uploaded=0&downloaded=0&left={left}&numwant=80&key={key:08X}&compact=1&supportcrypto=1&event=started",
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
    let (download_bps, upload_bps) = stats
        .live
        .as_ref()
        .map(|live| {
            (
                live.download_speed.mbps * 125_000.0,
                live.upload_speed.mbps * 125_000.0,
            )
        })
        .unwrap_or_default();

    TorrentSnapshot {
        id: handle.id() as u64,
        name: handle
            .name()
            .unwrap_or_else(|| handle.info_hash().as_string()),
        info_hash: handle.info_hash().as_string(),
        state: stats.state.to_string(),
        files,
        trackers,
        peers,
        progress_bytes: stats.progress_bytes,
        total_bytes: stats.total_bytes,
        uploaded_bytes: stats.uploaded_bytes,
        download_bps,
        upload_bps,
        error: stats.error,
    }
}

fn snapshot_trackers(handle: &Arc<ManagedTorrent>) -> Vec<TorrentTrackerSnapshot> {
    let mut trackers = handle
        .shared()
        .trackers
        .iter()
        .map(|url| url.to_string())
        .collect::<Vec<_>>();
    trackers.sort();
    trackers
        .into_iter()
        .enumerate()
        .map(|(idx, url)| TorrentTrackerSnapshot {
            id: idx as u64,
            url,
        })
        .collect()
}

fn snapshot_peers(handle: &Arc<ManagedTorrent>) -> Vec<TorrentPeerSnapshot> {
    let Some(live) = handle.live() else {
        return Vec::new();
    };

    let mut peers = live
        .per_peer_stats_snapshot(PeerStatsFilter::default())
        .peers
        .into_iter()
        .map(|(address, peer)| TorrentPeerSnapshot {
            id: address.clone(),
            address,
            state: peer.state.to_owned(),
            connection_kind: peer.conn_kind.map(|kind| kind.to_string()),
            downloaded_bytes: peer.counters.fetched_bytes,
            uploaded_bytes: peer.counters.uploaded_bytes,
            connection_attempts: peer.counters.connection_attempts,
            connections: peer.counters.connections,
            errors: peer.counters.errors,
        })
        .collect::<Vec<_>>();
    peers.sort_by(|lhs, rhs| lhs.address.cmp(&rhs.address));
    peers
}

fn snapshot_files(handle: &Arc<ManagedTorrent>, file_progress: &[u64]) -> Vec<TorrentFileSnapshot> {
    let only_files = handle.only_files();
    handle
        .with_metadata(|metadata| {
            metadata
                .file_infos
                .iter()
                .enumerate()
                .map(|(idx, file)| TorrentFileSnapshot {
                    id: idx as u64,
                    path: file.relative_filename.to_string_lossy().into_owned(),
                    length: file.len,
                    progress_bytes: file_progress.get(idx).copied().unwrap_or_default(),
                    included: only_files
                        .as_ref()
                        .map(|files| files.contains(&idx))
                        .unwrap_or(true),
                    is_padding: file.attrs.padding,
                })
                .collect()
        })
        .unwrap_or_default()
}
