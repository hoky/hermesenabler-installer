//! Retry only failures while establishing a connection. A developer POST may
//! create/revoke certificates, so never replay it after a response/read failure.
use reqwest::Response;
use reqwest_middleware::RequestBuilder;
use std::time::Duration;

fn retryable_connect_error(error: &reqwest_middleware::Error) -> bool {
    let reqwest_middleware::Error::Reqwest(error) = error else {
        return false;
    };
    // Hyper marks handshake failures as Connect even when io::Error hides the
    // nested UnexpectedEof in its source chain. This also covers native TLS.
    // The HTTP POST has not been sent at this stage. Certificate verification
    // remains enabled on every attempt; a persistent rejection still fails.
    error.is_connect()
}

pub(super) async fn send(request: RequestBuilder) -> reqwest_middleware::Result<Response> {
    send_with_delay(request, Duration::from_secs(1)).await
}

async fn send_with_delay(
    request: RequestBuilder,
    delay: Duration,
) -> reqwest_middleware::Result<Response> {
    // These requests have an in-memory plist body. If another caller supplies a
    // streaming body, send it once instead of assuming it can be replayed.
    if request.try_clone().is_none() {
        return request.send().await;
    }
    for attempt in 0..4 {
        let result = request
            .try_clone()
            .expect("cloneable plist request")
            .send()
            .await;
        match result {
            Err(ref error) if attempt < 3 && retryable_connect_error(error) => {
                eprintln!(
                    "[网络] Apple 服务连接中断，{} 秒后重试（{}/3）…",
                    delay.as_secs() * (1 << attempt),
                    attempt + 1
                );
                tokio::time::sleep(delay * (1 << attempt)).await;
            }
            result => return result,
        }
    }
    unreachable!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    struct Flaky {
        calls: Arc<AtomicUsize>,
        failures: usize,
        status: u16,
        builder_error: bool,
    }

    #[async_trait::async_trait]
    impl reqwest_middleware::Middleware for Flaky {
        async fn handle(
            &self,
            request: reqwest::Request,
            _: &mut http::Extensions,
            _: reqwest_middleware::Next<'_>,
        ) -> reqwest_middleware::Result<reqwest::Response> {
            let attempt = self.calls.fetch_add(1, Ordering::SeqCst);
            assert_eq!(
                request.body().unwrap().as_bytes().unwrap(),
                b"synthetic plist"
            );
            if self.builder_error {
                return Err(reqwest::Client::new()
                    .get("invalid URL")
                    .build()
                    .unwrap_err()
                    .into());
            }
            if attempt < self.failures {
                // Local TLS peer closes before its handshake: reproduce the
                // reported EOF without Apple credentials or external traffic.
                let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
                let addr = listener.local_addr().unwrap();
                let peer = std::thread::spawn(move || {
                    let (socket, _) = listener.accept().unwrap();
                    drop(socket);
                });
                let error = reqwest::Client::builder()
                    .no_proxy()
                    .use_rustls_tls()
                    .timeout(Duration::from_secs(3))
                    .build()
                    .unwrap()
                    .post(format!("https://{addr}/"))
                    .send()
                    .await
                    .unwrap_err();
                peer.join().unwrap();
                return Err(error.into());
            }
            Ok(http::Response::builder()
                .status(self.status)
                .body("synthetic response")
                .unwrap()
                .into())
        }
    }

    async fn run(
        failures: usize,
        status: u16,
        builder_error: bool,
    ) -> (reqwest_middleware::Result<Response>, usize) {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let calls = Arc::new(AtomicUsize::new(0));
        let client = reqwest_middleware::ClientBuilder::new(reqwest::Client::new())
            .with(Flaky {
                calls: calls.clone(),
                failures,
                status,
                builder_error,
            })
            .build();
        let result = send_with_delay(
            client
                .post("https://synthetic.invalid/updateAppId.action")
                .body("synthetic plist"),
            Duration::ZERO,
        )
        .await;
        (result, calls.load(Ordering::SeqCst))
    }

    #[tokio::test]
    async fn recovers_from_tls_eof_and_preserves_post_body() {
        let (result, calls) = run(2, 200, false).await;
        assert!(result.is_ok(), "{result:?}");
        assert_eq!(calls, 3);
    }
    #[tokio::test]
    async fn stops_after_four_connection_attempts() {
        let (result, calls) = run(10, 200, false).await;
        assert!(result.is_err());
        assert_eq!(calls, 4);
    }
    #[tokio::test]
    async fn never_replays_server_rejections() {
        for status in [403, 429, 503] {
            let (result, calls) = run(0, status, false).await;
            assert_eq!(result.unwrap().status().as_u16(), status);
            assert_eq!(calls, 1);
        }
    }
    #[tokio::test]
    async fn never_retries_invalid_requests() {
        let (result, calls) = run(0, 200, true).await;
        assert!(result.is_err());
        assert_eq!(calls, 1);
    }

    #[tokio::test]
    #[ignore = "explicit, credential-free live Apple network diagnostic"]
    async fn check_apple_connection_with_retries() {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let client = crate::auth::grandslam::GrandSlam::build_reqwest_client(false, None).unwrap();
        for attempt in 1..=10 {
            let response = send(
                client
                    .get("https://developerservices2.apple.com/")
                    .header("Connection", "close"),
            )
            .await
            .unwrap();
            println!("Apple connection {attempt}/10: HTTP {}", response.status());
            // An unauthenticated 401 still confirms a completed TLS handshake.
            response.bytes().await.unwrap();
        }
    }
}
