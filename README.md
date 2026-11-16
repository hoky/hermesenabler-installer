# HermesEnabler 安装器

## 本地修复版 1.0.1

- Apple 请求增加连接和请求超时，保留原有 TLS 实现和证书校验。
- Apple 开发者请求在建立连接失败时按 1、2、4 秒退避重试，最多共 4 次。服务器拒绝、响应读取失败等不会重复提交，以免重复创建或吊销证书。
- 删除写死的作者手表 UDID；在界面填写自己的「手表 UDID」，Xcode 27 可从 Xcode → Open Developer Tool → Device Hub 配对并查看，旧版 Xcode 则使用 Window → Devices and Simulators。命令行通过 `WATCH_UDID` 指定。手表注册失败时停止，安装失败不再显示成功。
- 构建产物：`build/HermesEnabler-Fixed.app`，可与原版并存。
- 无账户网络检查：`build/HermesEnabler-Fixed.app/Contents/MacOS/hcli --check-network`。

源码修复和网络检查不能代替真实签名验证，最后需要用户在修复版中登录并完成安装。

[English](README.en.md) · **中文**

一个 macOS 图形工具：用**免费 Apple ID** 给 HermesEnabler 签名，把 iPhone 和 Apple Watch 一次装好，并且把 **App Group** 正确写进 Watch 的 provisioning profile。

![安装器界面](docs/images/screenshot-main.png)

之所以有这个工具，是因为现有的侧载工具都会在某一步卡死：

| 工具 | 卡在哪 |
|---|---|
| Sideloadly（免费账号） | 不把 Watch 的 UDID 写进 profile，也完全不处理 Watch app |
| AltStore / SideStore | Watch UDID 缺失 → `0xe8008015` 安装失败 |
| Xcode（免费团队） | 拒绝授予 `com.apple.security.application-groups` |
| 上游 isideload | 关联 App Group 时用 `continue` 把 Watch app 跳过了 |

最后一条是根本原因。这个项目把它修了，然后用两条独立的安装通道——手机走 `installation_proxy`，手表走 `devicectl`——所以不依赖手机是否暴露那个老的 companion-proxy 服务。

> 改 MobileGestalt 属于非官方操作，可能导致设备异常，风险自负。与 Apple Inc. 无任何关系。

---

## 普通用户：怎么装

1. 从 [Releases](../../releases) 下载 `HermesEnabler-Installer-1.0.dmg`
2. 打开镜像，把 App 拖进 `Applications`
3. **首次打开**：右键点 App → **打开** → 再点一次**打开**
   （ad-hoc 签名，没做 Apple 公证，Gatekeeper 会拦一次；或者终端里跑 `xattr -cr /Applications/HermesEnabler.app`）
4. 从 [pookjw/HermesEnabler/releases](https://github.com/pookjw/HermesEnabler/releases) 下载**原版 IPA**（别用别人改过 bundle ID 的）
5. 填 Apple ID、选 IPA、点「开始安装」
6. 弹出验证码输入框时填手机收到的 6 位数字
7. 跑完后：
   - iPhone：**设置 → 通用 → VPN 与设备管理 → Apple Development: 你的邮箱 → 信任**
   - iPhone 的 **Watch App → 我的手表 → 可用 App → HermesEnabler → 安装**
8. 手表上打开 HermesEnabler，**先点 `Backup MG` 备份**，再动任何开关

## 环境要求

- macOS 13 及以上
- 装了 Xcode 或 Xcode Command Line Tools（`xcrun` 能用）
- 一个 Apple ID（免费的就行）
- iPhone 开启开发者模式，用数据线连 Mac 并已信任
- Apple Watch 与这台 iPhone 配对，且开启开发者模式
- 网络能访问 `gsa.apple.com`、`idmsa.apple.com`、`developerservices2.apple.com`，
  以及一个 anisette 服务（默认 `https://ani.stikstore.app`）

如果这些域名不通，需要走代理，否则登录或 `listTeams` 会报 `tls handshake eof`。

## 已知限制

- 免费证书 **7 天**过期。到期后 App 打不开，重跑一次安装器即可续期，Bundle ID 不变所以数据不丢
- 免费账号只能有 **1 张**开发证书。遇到 `7460` 时安装器会吊销旧证书——用那张证书签过的 App 会失效
- 改过 MobileGestalt 之后**不要再点 `Backup MG`**，否则会用改后的状态覆盖掉干净备份
- 表盘修改后如果没生效，重启一次手表

## 从源码构建

```bash
cargo build --release                 # 命令行
./scripts/build.sh                    # 命令行 + 界面 + .app
./scripts/make-dmg.sh                 # 生成 dist/*.dmg
```

目录结构：

```
src/main.rs          命令行：登录 → 签名 → 装手机 → 推手表
gui/main.swift       SwiftUI 外壳
vendor/isideload/    打过补丁的 isideload 0.3.17
scripts/build.sh     组装 HermesEnabler.app
scripts/make-dmg.sh  打 DMG
assets/AppIcon.icns  图标（SF Symbol 手表）
docs/PATCHES.md      改了 isideload 哪些地方、为什么
```

## 两处上游补丁

细节和证据见 [docs/PATCHES.md](docs/PATCHES.md)。摘要：

1. **`anisette/remote_v3/mod.rs`** —— `client_info` 改成从 anisette 服务器的
   `/v3/client_info` 拉取。Apple 从 2026-10-12 起会拒绝 client_info 不匹配的请求。
2. **`sideload/sideloader.rs`** —— 关联 App Group 时不再跳过 Watch app，
   用 `DeveloperDeviceType::Watchos` 一起关联。

## 关于这个项目

这个工具是在 AI 辅助下做出来的。作者是第一次做这类东西，对开源流程、提 PR 这些几乎没经验。
在作者自己的机器上（iPhone 17 Pro + Apple Watch，watchOS 27）是能跑通的，但用之前请自行判断风险。
发现问题欢迎提 issue 指正。

## 许可

MIT，见 [LICENSE](LICENSE)。链接的 crate 及 SPDX 标识见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

上游：[HermesEnabler](https://github.com/pookjw/HermesEnabler)（MIT）、
[iloader](https://github.com/nab138/iloader)（MIT）、
[isideload](https://github.com/nab138/isideload)（MIT）。
