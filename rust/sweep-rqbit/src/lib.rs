use std::{
    collections::HashMap,
    ffi::{CStr, CString},
    os::raw::c_char,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use anyhow::{Context, Result, bail};
use librqbit::{AddTorrent, AddTorrentOptions, AddTorrentResponse, ManagedTorrent, Session};
use serde::Serialize;
use tokio::runtime::{Builder, Runtime};

pub struct SweepClient {
    runtime: Runtime,
    session: Arc<Session>,
    handles: Mutex<HashMap<usize, Arc<ManagedTorrent>>>,
}

#[derive(Serialize)]
struct TorrentSnapshot {
    id: usize,
    name: String,
    info_hash: String,
    state: String,
    progress_bytes: u64,
    total_bytes: u64,
    uploaded_bytes: u64,
    download_bps: f64,
    upload_bps: f64,
    error: Option<String>,
}

#[derive(Serialize)]
struct AddTorrentSnapshot {
    torrent: TorrentSnapshot,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sweep_client_create(
    download_dir: *const c_char,
    error_out: *mut *mut c_char,
) -> *mut SweepClient {
    match create_client(download_dir) {
        Ok(client) => Box::into_raw(Box::new(client)),
        Err(error) => {
            write_error(error_out, error);
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sweep_client_destroy(client: *mut SweepClient) {
    if !client.is_null() {
        drop(unsafe { Box::from_raw(client) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sweep_client_add_magnet(
    client: *mut SweepClient,
    magnet: *const c_char,
    json_out: *mut *mut c_char,
    error_out: *mut *mut c_char,
) -> bool {
    match with_client(client, |client| add_magnet(client, magnet)) {
        Ok(json) => {
            write_string(json_out, json);
            true
        }
        Err(error) => {
            write_error(error_out, error);
            false
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sweep_client_list(
    client: *mut SweepClient,
    json_out: *mut *mut c_char,
    error_out: *mut *mut c_char,
) -> bool {
    match with_client(client, list_torrents) {
        Ok(json) => {
            write_string(json_out, json);
            true
        }
        Err(error) => {
            write_error(error_out, error);
            false
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sweep_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

fn create_client(download_dir: *const c_char) -> Result<SweepClient> {
    let download_dir = c_string(download_dir, "download_dir")?;
    let runtime = Builder::new_multi_thread()
        .enable_all()
        .thread_name("sweep-rqbit")
        .build()
        .context("failed to create rqbit runtime")?;
    let session = runtime
        .block_on(Session::new(PathBuf::from(download_dir)))
        .context("failed to create rqbit session")?;

    Ok(SweepClient {
        runtime,
        session,
        handles: Mutex::new(HashMap::new()),
    })
}

fn add_magnet(client: &SweepClient, magnet: *const c_char) -> Result<String> {
    let magnet = c_string(magnet, "magnet")?;
    let response = client.runtime.block_on(async {
        client
            .session
            .add_torrent(
                AddTorrent::from_url(&magnet),
                Some(AddTorrentOptions {
                    overwrite: true,
                    ..Default::default()
                }),
            )
            .await
    })?;

    let handle = match response {
        AddTorrentResponse::Added(_, handle) => handle,
        AddTorrentResponse::AlreadyManaged(_, handle) => handle,
        AddTorrentResponse::ListOnly(_) => bail!("list-only responses are not used by Sweep"),
    };
    let id = handle.id();
    client
        .handles
        .lock()
        .expect("torrent handle lock poisoned")
        .insert(id, handle.clone());

    serde_json::to_string(&AddTorrentSnapshot {
        torrent: snapshot(&handle),
    })
    .context("failed to encode add torrent response")
}

fn list_torrents(client: &SweepClient) -> Result<String> {
    let handles = client
        .handles
        .lock()
        .expect("torrent handle lock poisoned")
        .values()
        .cloned()
        .collect::<Vec<_>>();
    let snapshots = handles.iter().map(snapshot).collect::<Vec<_>>();
    serde_json::to_string(&snapshots).context("failed to encode torrent list")
}

fn snapshot(handle: &Arc<ManagedTorrent>) -> TorrentSnapshot {
    let stats = handle.stats();
    let (download_bps, upload_bps) = stats
        .live
        .as_ref()
        .map(|live| (live.download_speed.mbps * 125_000.0, live.upload_speed.mbps * 125_000.0))
        .unwrap_or_default();

    TorrentSnapshot {
        id: handle.id(),
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

fn with_client<T>(
    client: *mut SweepClient,
    f: impl FnOnce(&SweepClient) -> Result<T>,
) -> Result<T> {
    if client.is_null() {
        bail!("rqbit client was not created");
    }
    f(unsafe { &*client })
}

fn c_string(value: *const c_char, name: &str) -> Result<String> {
    if value.is_null() {
        bail!("{name} was null");
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .with_context(|| format!("{name} was not valid UTF-8"))
        .map(ToOwned::to_owned)
}

fn write_error(error_out: *mut *mut c_char, error: anyhow::Error) {
    write_string(error_out, format!("{error:#}"));
}

fn write_string(out: *mut *mut c_char, value: String) {
    if out.is_null() {
        return;
    }
    let sanitized = value.replace('\0', "");
    let c_string = CString::new(sanitized).expect("nul bytes were removed");
    unsafe {
        *out = c_string.into_raw();
    }
}
