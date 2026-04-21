use std::{path::PathBuf, sync::Arc};

use anyhow::Context;
use futures_channel::oneshot;
use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, ManagedTorrent, Session,
    api::TorrentIdOrHash,
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
pub struct TorrentSnapshot {
    pub id: u64,
    pub name: String,
    pub info_hash: String,
    pub state: String,
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
            .block_on(Session::new(PathBuf::from(download_dir)))
            .context("failed to create rqbit session")?;

        Ok(Arc::new(Self { runtime, session }))
    }

    pub async fn add_magnet(
        &self,
        magnet: String,
        start_paused: bool,
    ) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = add_magnet_to_session(session, magnet, start_paused).await;
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

async fn add_magnet_to_session(
    session: Arc<Session>,
    magnet: String,
    start_paused: bool,
) -> Result<TorrentSnapshot, SweepError> {
    let response = session
        .add_torrent(
            AddTorrent::from_url(&magnet),
            Some(AddTorrentOptions {
                overwrite: true,
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
        progress_bytes: stats.progress_bytes,
        total_bytes: stats.total_bytes,
        uploaded_bytes: stats.uploaded_bytes,
        download_bps,
        upload_bps,
        error: stats.error,
    }
}
