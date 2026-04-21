use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use anyhow::Context;
use futures_channel::oneshot;
use librqbit::{AddTorrent, AddTorrentOptions, AddTorrentResponse, ManagedTorrent, Session};
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
    handles: Arc<Mutex<HashMap<u64, Arc<ManagedTorrent>>>>,
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

        Ok(Arc::new(Self {
            runtime,
            session,
            handles: Arc::new(Mutex::new(HashMap::new())),
        }))
    }

    pub async fn add_magnet(&self, magnet: String) -> Result<TorrentSnapshot, SweepError> {
        let session = self.session.clone();
        let handles = self.handles.clone();
        let runtime = self.runtime.handle().clone();
        let (tx, rx) = oneshot::channel();

        runtime.spawn(async move {
            let result = add_magnet_to_session(session, handles, magnet).await;
            let _ = tx.send(result);
        });

        rx.await?
    }

    pub async fn list_torrents(&self) -> Result<Vec<TorrentSnapshot>, SweepError> {
        let handles = self
            .handles
            .lock()
            .expect("torrent handle lock poisoned")
            .values()
            .cloned()
            .collect::<Vec<_>>();
        Ok(handles.iter().map(snapshot).collect())
    }
}

async fn add_magnet_to_session(
    session: Arc<Session>,
    handles: Arc<Mutex<HashMap<u64, Arc<ManagedTorrent>>>>,
    magnet: String,
) -> Result<TorrentSnapshot, SweepError> {
    let response = session
        .add_torrent(
            AddTorrent::from_url(&magnet),
            Some(AddTorrentOptions {
                overwrite: true,
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

    let id = handle.id() as u64;
    handles
        .lock()
        .expect("torrent handle lock poisoned")
        .insert(id, handle.clone());

    Ok(snapshot(&handle))
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
