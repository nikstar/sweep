use std::{path::PathBuf, sync::Arc};

use anyhow::Context;
use futures_channel::oneshot;
use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, ConnectionOptions, ListenerMode,
    ListenerOptions, ManagedTorrent, Session, SessionOptions, api::TorrentIdOrHash,
    http_api_types::PeerStatsFilter,
};
use tokio::runtime::{Builder, Runtime};

uniffi::setup_scaffolding!();

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
        let session = runtime
            .block_on(Session::new_with_opts(
                PathBuf::from(download_dir),
                SessionOptions {
                    disable_dht_persistence: true,
                    listen: Some(ListenerOptions {
                        mode: ListenerMode::TcpAndUtp,
                        ..Default::default()
                    }),
                    connect: Some(ConnectionOptions::default()),
                    ..Default::default()
                },
            ))
            .context("failed to create rqbit session")?;

        Ok(Arc::new(Self { runtime, session }))
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
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = add_torrent_to_session(
                session,
                AddTorrent::from_bytes(torrent_bytes),
                download_dir,
                start_paused,
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
) -> Result<TorrentSnapshot, SweepError> {
    let response = session
        .add_torrent(
            add_torrent,
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(download_dir),
                paused: start_paused,
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
