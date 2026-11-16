//! Minimal macOS CLI: login with Apple ID, sign an IPA (including the embedded
//! Watch app, with App Groups), and install it on a USB/Wi-Fi attached iPhone.
//!
//! Usage:
//!   APPLE_ID=you@example.com hcli <app.ipa> [device-udid]
//!
//! Password is read from stdin (not echoed) unless APPLE_PASSWORD is set.

use std::future::Future;
use std::io::{self, BufRead, Write};
use std::pin::Pin;

use futures::FutureExt;
use idevice::usbmuxd::{UsbmuxdAddr, UsbmuxdConnection};

use isideload::anisette::remote_v3::RemoteV3AnisetteProvider;
use isideload::auth::apple_account::{
    AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse,
};
use isideload::dev::developer_session::DeveloperSession;
use isideload::dev::device_type::DeveloperDeviceType;
use isideload::dev::devices::DevicesApi;
use isideload::sideload::SideloaderBuilder;
use isideload::sideload::builder::MaxCertsBehavior;
use isideload::util::storage::new_storage;

type TfaBox = Box<
    dyn Fn(
            TwoFactorCallbackParams,
        ) -> Pin<
            Box<dyn Future<Output = Result<TwoFactorCallbackResponse, rootcause::Report>> + Send>,
        > + Send
        + Sync,
>;

fn read_line(prompt: &str) -> String {
    print!("{prompt}");
    io::stdout().flush().ok();
    let mut s = String::new();
    io::stdin().lock().read_line(&mut s).ok();
    s.trim().to_string()
}

fn read_password(prompt: &str) -> String {
    // stty -echo; read; stty echo
    let _ = std::process::Command::new("stty").arg("-echo").status();
    let v = read_line(prompt);
    let _ = std::process::Command::new("stty").arg("echo").status();
    println!();
    v
}

#[tokio::main]
async fn main() -> Result<(), rootcause::Report> {
    // rustls 0.23 + rustls-no-provider: must install a provider before any Client is built,
    // otherwise reqwest panics on the first HTTPS request.
    let _ = rustls::crypto::ring::default_provider().install_default();
    isideload::init().ok();

    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("--check-network") {
        let client = isideload::auth::grandslam::GrandSlam::build_reqwest_client(false, None)?;
        for attempt in 1..=5 {
            let response = client
                .get("https://developerservices2.apple.com/")
                .header("Connection", "close")
                .send()
                .await?;
            println!(
                "[网络] Apple TLS 检查 {attempt}/5: HTTP {}",
                response.status()
            );
            response.bytes().await?;
        }
        println!("[+] 网络检查通过（未登录，未提交签名或设备更改）");
        return Ok(());
    }
    if args.len() < 2 {
        eprintln!(
            "用法: WATCH_UDID=你的手表UDID APPLE_ID=you@example.com hcli <app.ipa> [device-udid]\n网络检查: hcli --check-network"
        );
        std::process::exit(2);
    }
    let ipa = std::path::PathBuf::from(&args[1]);
    if !ipa.exists() {
        eprintln!("找不到 IPA: {}", ipa.display());
        std::process::exit(2);
    }
    let want_udid = args
        .get(2)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());

    // Never register or install onto a developer's hard-coded Watch.
    let watch_udid = std::env::var("WATCH_UDID")
        .ok().map(|s| s.trim().to_owned()).filter(|s| !s.is_empty())
        .ok_or_else(|| rootcause::report!("请填写你自己的 Apple Watch UDID（可在 Xcode 的 Device Hub（旧版为 Devices and Simulators）查看），然后重新开始。"))?;

    let email = std::env::var("APPLE_ID").unwrap_or_else(|_| read_line("Apple ID: "));
    let password = std::env::var("APPLE_PASSWORD").unwrap_or_else(|_| read_password("Password: "));
    let anisette_url =
        std::env::var("ANISETTE_URL").unwrap_or_else(|_| "https://ani.stikstore.app".to_string());

    println!("[*] Apple ID: {email}");
    println!("[*] anisette: {anisette_url}");

    // ---- 1. anisette provider -------------------------------------------------
    let anisette = RemoteV3AnisetteProvider::default()?
        .set_serial_number("0".to_string())
        .set_storage(Box::new(new_storage()))
        .set_url(&anisette_url);

    // ---- 2. login -------------------------------------------------------------
    let tfa: TfaBox = Box::new(|_params: TwoFactorCallbackParams| {
        async move {
            let code = read_line("2FA code: ");
            if code.is_empty() {
                return Ok(TwoFactorCallbackResponse::Abort);
            }
            Ok(TwoFactorCallbackResponse::SubmitCode(code))
        }
        .boxed()
    });

    let mut account = AppleAccount::builder(&email.to_lowercase())
        .anisette_provider(anisette)
        .login(&password, tfa)
        .await?;
    println!("[+] 登录成功");

    // ---- 3. developer session -------------------------------------------------
    let dev_session = DeveloperSession::from_account(&mut account).await?;
    println!("[+] 开发者会话已建立");

    // ---- 4. pick device -------------------------------------------------------
    let mut conn = UsbmuxdConnection::default().await?;
    let devices = conn.get_devices().await?;
    if devices.is_empty() {
        return Err(rootcause::report!(
            "usbmuxd 没有发现任何设备（iPhone 是否插好并已信任？）"
        ));
    }
    let dev = match &want_udid {
        Some(u) => devices
            .iter()
            .find(|d| d.udid == *u)
            .ok_or_else(|| rootcause::report!("未找到设备 {}", u))?,
        None => devices
            .first()
            .ok_or_else(|| rootcause::report!("无设备"))?,
    };
    let addr = UsbmuxdAddr::from_env_var()
        .unwrap_or_else(|_| UsbmuxdAddr::UnixSocket(UsbmuxdAddr::SOCKET_FILE.to_string()));
    let provider = dev.to_provider(addr, "hcli");
    println!("[+] 目标设备: {} ({})", dev.udid, dev.device_id);

    // ---- 5. sign + install ----------------------------------------------------
    let mut sideloader = SideloaderBuilder::new(dev_session, email.clone())
        .machine_name("hcli".to_string())
        .max_certs_behavior(MaxCertsBehavior::Revoke)
        .delete_app_after_install(false)
        .build();

    // 先把手表 UDID 注册进团队，否则 watch app 的 profile 里不会有它。
    let team = sideloader.get_team().await?;
    sideloader
        .get_dev_session()
        .ensure_device_registered(
            &team,
            "Apple Watch",
            &watch_udid,
            Some(DeveloperDeviceType::Watchos),
        )
        .await?;
    println!("[+] 手表已注册为开发设备: {watch_udid}");

    println!("[*] 签名中（含内嵌 Watch app 与 App Group）…");
    let (signed, special) = sideloader
        .sign_app(
            ipa,
            None,
            false,
            Some(|p: f32| async move {
                print!("\r    签名 {:.0}%", p * 100.0);
                io::stdout().flush().ok();
            }),
        )
        .await?;
    println!("\n[+] 签名完成: {}", signed.display());
    if let Some(s) = special {
        println!("    特殊处理: {s:?}");
    }

    println!("[*] 安装到设备…");
    let result = sideloader
        .install_app(
            &provider,
            signed.clone(),
            false,
            Some(|p: f32| async move {
                print!("\r    安装 {:.0}%", p * 100.0);
                io::stdout().flush().ok();
            }),
        )
        .await?;
    println!("\n[+] iPhone 安装完成: {result:?}");

    // 手机端的 legacy companion proxy 不走，改用 Xcode 的 devicectl 通道推手表
    let watch_dir = signed.join("Watch");
    if watch_dir.exists() {
        if let Ok(entries) = std::fs::read_dir(&watch_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map(|e| e == "app").unwrap_or(false) {
                    println!("[*] 正在把手表 App 推到 {} …", watch_udid);
                    let out = std::process::Command::new("/usr/bin/xcrun")
                        .args([
                            "devicectl",
                            "device",
                            "install",
                            "app",
                            "--device",
                            &watch_udid,
                            path.to_str().unwrap_or_default(),
                        ])
                        .env(
                            "DEVELOPER_DIR",
                            "/Applications/Xcode.app/Contents/Developer",
                        )
                        .output();
                    match out {
                        Ok(o) => {
                            let so = String::from_utf8_lossy(&o.stdout);
                            let se = String::from_utf8_lossy(&o.stderr);
                            println!("{so}{se}");
                            if o.status.success() {
                                println!("[+] 手表安装成功");
                            } else {
                                return Err(rootcause::report!(
                                    "手表安装失败（退出码 {}），请查看上面的 devicectl 错误。",
                                    o.status.code().unwrap_or(-1)
                                ));
                            }
                        }
                        Err(e) => return Err(rootcause::report!("调用 devicectl 失败: {e}")),
                    }
                }
            }
        }
    } else {
        return Err(rootcause::report!(
            "签名产物里没有 Watch 目录: {}",
            watch_dir.display()
        ));
    }

    Ok(())
}
