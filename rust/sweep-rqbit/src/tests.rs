use super::*;
use std::{
    fs,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        static NEXT_ID: AtomicU64 = AtomicU64::new(0);
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "sweep-rqbit-test-{}-{stamp}-{}",
            std::process::id(),
            NEXT_ID.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn folder(&self, name: &str) -> PathBuf {
        let path = self.0.join(name);
        fs::create_dir_all(&path).unwrap();
        path
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn local_engine(path: PathBuf) -> Arc<SweepEngine> {
    let runtime = Builder::new_multi_thread().enable_all().build().unwrap();
    let session = runtime
        .block_on(Session::new_with_opts(
            path,
            SessionOptions {
                disable_dht: true,
                disable_local_service_discovery: true,
                listen: Some(ListenerOptions {
                    mode: ListenerMode::TcpOnly,
                    listen_addr: "127.0.0.1:0".parse().unwrap(),
                    ..Default::default()
                }),
                connect: Some(ConnectionOptions::default()),
                ..Default::default()
            },
        ))
        .unwrap();
    Arc::new(SweepEngine {
        runtime,
        session,
        peer_id: tracker_compatible_peer_id(),
        pending_adds: Mutex::new(HashMap::new()),
        discoveries: Mutex::new(HashMap::new()),
    })
}

#[test]
fn resolves_magnet_transfers_payload_and_restores_cached_metadata() {
    let fixture = Fixture::new();
    let seed_dir = fixture.folder("seed");
    let download_dir = fixture.folder("download");
    let payload: Vec<u8> = (0..1_048_576).map(|n| (n % 251) as u8).collect();
    let payload_path = seed_dir.join("payload.bin");
    fs::write(&payload_path, &payload).unwrap();
    let seed = local_engine(seed_dir);
    let download = local_engine(download_dir.clone());
    seed.runtime.block_on(async {
        let (_, seed_handle) = seed
            .session
            .create_and_serve_torrent(
                &payload_path,
                librqbit::CreateTorrentOptions {
                    piece_length: Some(65536),
                    ..Default::default()
                },
            )
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(10), async {
            while !seed_handle.stats().finished {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .unwrap();
        let (tracker_url, request) = serve_tracker(seed.session.listen_addr().unwrap()).await;
        let magnet = format!(
            "magnet:?xt=urn:btih:{}&tr={tracker_url}",
            seed_handle.info_hash().as_string()
        );
        let added = tokio::time::timeout(
            Duration::from_secs(10),
            download.add_magnet(magnet, download_dir.to_str().unwrap().to_owned(), false),
        )
        .await
        .expect("local magnet discovery timed out")
        .unwrap();
        let request = request.await.unwrap();
        assert!(request.contains("supportcrypto=0"), "{request}");
        assert!(!request.contains("supportcrypto=1"));
        assert!(
            request.contains("&left=1&"),
            "an unresolved magnet must not announce as a seed: {request}"
        );
        let id = added.info_hash;
        tokio::time::timeout(Duration::from_secs(15), async {
            loop {
                let snapshot = download.list_torrents().await.unwrap().remove(0);
                assert!(snapshot.error.is_none(), "{:?}", snapshot.error);
                if snapshot.state == "live" && snapshot.progress_bytes == payload.len() as u64 {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(25)).await;
            }
        })
        .await
        .expect("local payload transfer timed out");
        assert!(
            fs::read(download_dir.join("payload.bin")).unwrap() == payload,
            "downloaded payload did not match the seeded bytes"
        );
        let metadata = download.torrent_file(id.clone()).unwrap();
        download.remove_torrent(id.clone(), false).await.unwrap();
        let restored = download
            .add_torrent_file(metadata, download_dir.to_str().unwrap().to_owned(), true)
            .await
            .unwrap();
        assert_eq!(restored.info_hash, id);
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = download.list_torrents().await.unwrap().remove(0);
                if snapshot.state == "paused" {
                    assert_eq!(snapshot.progress_bytes, payload.len() as u64);
                    break;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("restoration did not reach paused state");
    });
}

#[test]
fn cancelling_metadata_discovery_aborts_the_rust_task() {
    let fixture = Fixture::new();
    let engine = local_engine(fixture.folder("download"));
    engine.runtime.block_on(async {
        // A local tracker that never responds keeps discovery pending, without
        // relying on an external network or on a particular public swarm.
        let tracker = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let id = "0123456789abcdef0123456789abcdef01234567";
        let magnet = format!(
            "magnet:?xt=urn:btih:{id}&tr=http://{}/announce",
            tracker.local_addr().unwrap()
        );
        let task_engine = engine.clone();
        let task = tokio::spawn(async move {
            task_engine
                .add_magnet(magnet, "/unused".to_owned(), true)
                .await
        });
        tokio::time::timeout(Duration::from_secs(2), async {
            while engine.pending_adds.lock().unwrap().is_empty() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        engine.cancel_pending_add(id.to_owned());
        let result = tokio::time::timeout(Duration::from_secs(2), task)
            .await
            .unwrap()
            .unwrap();
        assert!(result.is_err());
        assert!(engine.pending_adds.lock().unwrap().is_empty());
        assert!(engine.discovery_snapshots().is_empty());
        assert!(engine.list_torrents().await.unwrap().is_empty());
    });
}

async fn serve_tracker(peer: SocketAddr) -> (String, tokio::task::JoinHandle<String>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/announce", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut request = Vec::new();
        while !request.ends_with(b"\r\n\r\n") {
            request.push(socket.read_u8().await.unwrap());
            assert!(request.len() < 8192);
        }
        let SocketAddr::V4(peer) = peer else {
            panic!("test uses IPv4")
        };
        let mut body = b"d8:intervali1800e8:completei1e10:incompletei0e5:peers6:".to_vec();
        body.extend(peer.ip().octets());
        body.extend(peer.port().to_be_bytes());
        body.push(b'e');
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            body.len()
        );
        socket.write_all(response.as_bytes()).await.unwrap();
        socket.write_all(&body).await.unwrap();
        String::from_utf8(request).unwrap()
    });
    (url, task)
}

#[test]
fn reports_tracker_and_peer_failures_before_metadata() {
    let fixture = Fixture::new();
    let engine = local_engine(fixture.folder("download"));
    engine.runtime.block_on(async {
        let peer = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let (tracker_url, request) = serve_tracker(peer.local_addr().unwrap()).await;
        let reject = tokio::spawn(async move {
            let (mut socket, _) = peer.accept().await.unwrap();
            let mut handshake = [0; 68];
            socket.read_exact(&mut handshake).await.unwrap();
            // Reject the BitTorrent handshake, with no payload or metadata.
        });
        let id = "0123456789abcdef0123456789abcdef01234567";
        let task_engine = engine.clone();
        let task = tokio::spawn(async move {
            task_engine
                .add_magnet(
                    format!("magnet:?xt=urn:btih:{id}&tr={tracker_url}"),
                    "/unused".to_owned(),
                    true,
                )
                .await
        });
        let snapshot = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let Some(snapshot) = engine
                    .discovery_snapshots()
                    .into_iter()
                    .find(|s| s.peers_failed > 0)
                {
                    break snapshot;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("no discovery diagnostics");
        assert_eq!(snapshot.peers_found, 1);
        assert_eq!(snapshot.peers_tried, 1);
        assert_eq!(snapshot.peers_active, 0);
        assert_eq!(snapshot.peers_failed, 1);
        assert!(snapshot.is_active);
        assert!(snapshot.last_peer_error.unwrap().contains("handshake"));
        assert_eq!(snapshot.trackers[0].status, "Working");
        assert_eq!(snapshot.trackers[0].last_peer_count, Some(1));
        assert!(request.await.unwrap().contains("supportcrypto=0"));
        reject.await.unwrap();
        engine.cancel_pending_add(id.to_owned());
        assert!(
            tokio::time::timeout(Duration::from_secs(2), task)
                .await
                .unwrap()
                .unwrap()
                .is_err()
        );
    });
}
