# HermesEnabler 安装器

[English](README.en.md) · **中文**

一个 macOS 图形安装器，用 Apple ID 为 HermesEnabler 签名，处理 iPhone 主程序、内嵌 Apple Watch 应用及其 App Group。手机通过 `installation_proxy` 安装，手表通过 Xcode 的 `devicectl` 安装。

本 fork 的 **1.0.1 修复版**增加了 Apple 连接失败重试、明确的手表 UDID 输入、网络诊断和安装错误反馈。构建产物为 `HermesEnabler-Fixed.app`，可与原版并存。英文说明仍保留上游版本，修复版的操作步骤以本页为准。

> 修改 MobileGestalt 属于非官方操作。请先备份，在手表上的 HermesEnabler 中保存原始 MobileGestalt，再修改功能。本项目与 Apple Inc. 无关。

## 开始前准备

- macOS 13 或以上，以及 **完整的 Xcode**。只有 Command Line Tools、能运行 `xcrun`，并不代表可以使用 `devicectl` 安装手表应用。当前安装流程使用 `/Applications/Xcode.app/Contents/Developer`。
- 从源码构建还需要支持 Rust 2024 edition 的 Rust 工具链及 Cargo；建议安装当前稳定版。
- iPhone 已信任 Mac，开启开发者模式，使用数据线连接并保持解锁。
- Apple Watch 已与该 iPhone 配对，开启开发者模式，并在 Xcode 的设备工具中与 Mac 建立连接。**手机连接成功不等于手表也连接成功。**
- [HermesEnabler 官方 IPA](https://github.com/pookjw/HermesEnabler/releases)，包含 iPhone 主程序和 `Watch/*.app`。不要移除 Watch 应用或自行改写 Bundle ID。支持的 watchOS 版本以该项目当前说明为准。
- Mac 能访问 `gsa.apple.com`、`idmsa.apple.com`、`developerservices2.apple.com` 及 anisette 服务，默认服务为 `https://ani.stikstore.app`。

上游针对免费 Apple ID 实现了 Watch App Group 签名处理；这不代表任意账号、系统版本或网络都能安装成功。完整签名和手表安装仍需在自己的设备上验证。

## 构建修复版

在仓库根目录执行：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/build.sh
open build/HermesEnabler-Fixed.app
```

可选的磁盘镜像打包：

```bash
./scripts/make-dmg.sh
```

产物为 `dist/HermesEnabler-Installer-1.0.1-Fixed.dmg`。源码更新不等于已发布新的 Release；下载预编译包时请核对版本，旧版 `1.0` 不包含本页的连接重试和手表 UDID 输入修复。

## 获取自己的手表 UDID

这里需要 **UDID**，不是手表序列号，也不是 Mac 或其他工具生成的 UUID。

### Xcode 27.2：Device Hub

本次在 Xcode 27.2 上确认的入口为：

**Xcode → Open Developer Tool → Device Hub**

1. 在手表上打开「设置 → 隐私与安全性 → 开发者模式」，按提示重启并确认开启。
2. 保持手表解锁、靠近 Mac 和 iPhone，打开蓝牙，让 Mac 与手表连接同一 Wi-Fi；iPhone 保持 USB 连接。
3. 在 Device Hub 点击 **「＋ → Pair Nearby Device…」**，按设备上的提示完成配对。显示 `Waiting to pair` 时，检查手表上的开发者模式和配对提示。
4. 手表出现在设备列表后，选中真实手表并查看设备信息；也可以用下面的命令读取 UDID。

**不要选择「＋ → Apple Watch…」来连接真机：该菜单项属于模拟器创建入口。**

旧版 Xcode 使用 **Window → Devices and Simulators**。如果手表没有开发者模式入口，先核对手表系统版本及 Xcode 兼容性，不要用其他设备的标识代替。

### 用命令读取

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun devicectl list devices
```

找到型号为 Apple Watch 的真实设备，确认状态为 `connected`，读取标注为 `(UDID)` 的值。不要复制 iPhone 那一行。若输出中没有明确标注 UDID，可读取 JSON 中的 `hardwareProperties.udid`：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun devicectl list devices --json-output /tmp/hermes-devices.json

python3 - <<'PY'
import json
with open('/tmp/hermes-devices.json') as f:
    data = json.load(f)
for device in data.get('result', {}).get('devices', []):
    hardware = device.get('hardwareProperties', {})
    if hardware.get('platform') == 'watchOS':
        print(device.get('deviceProperties', {}).get('name'), hardware.get('udid'))
PY
```

只列出 iPhone 时，先完成手表配对，再重新查询。仅反复插拔 iPhone 不一定能让手表出现。

**程序没有内置任何人的手表 UDID。** 图形界面必须填写自己的「手表 UDID」；命令行通过 `WATCH_UDID` 提供，缺失时会在登录前停止。下文示例均使用占位符，不要把真实设备标识、Apple ID 密码或验证码提交到仓库。

## 安装步骤

1. 打开修复版，选择官方 `HermesEnabler.ipa`。
2. 输入自己的 Apple ID 和密码；填写上一步获取的 **手表 UDID**。如有多个设备连接，也请填写目标 iPhone 的「设备 UDID」。
3. 点击「开始安装」，收到双重认证验证码时，在安装器里输入。
4. 观察日志中的注册、签名、iPhone 安装和手表安装结果。**iPhone 安装成功不等于 Watch 安装成功。**
5. 如 iPhone 提示未受信任的开发者，在「设置 → 通用 → VPN 与设备管理」中信任对应签名账户，并确认两台设备都已开启开发者模式。
6. 手表安装成功后，打开 HermesEnabler，先点 `Backup MG` 保存原始备份，再进行功能修改。

命令行示例（将占位符换成自己的值，密码按提示输入）：

```bash
WATCH_UDID='<自己的手表UDID>' APPLE_ID='you@example.com' \
  ./target/release/hcli /path/to/HermesEnabler.ipa '<自己的iPhoneUDID>'
```

## 这次排错中遇到的问题

### AltServer 侧载后直接退出

本次在 AltServer 1.8.4 上出现两次相同位置的 `EXC_BAD_ACCESS / SIGSEGV`，HermesEnabler IPA 的解压完整性检查通过。日志能确认 AltServer 崩溃，但不足以确定具体是哪项包内容触发。

HermesEnabler 同时包含 iPhone 和 Watch 应用，不能直接套用普通 iPhone IPA（例如 GestaltX）的安装经验。即使另一工具把手机主程序装上，也要确认它保留并正确签名了 Watch 应用、配置描述文件和 App Group。

### 登录成功，签名 10% 报 `tls handshake eof`

典型错误链：

```text
Failed to update developer app ID
... developerservices2.apple.com/.../updateAppId.action ...
... Connect ... UnexpectedEof ... tls handshake eof
```

这表示请求在建立 TLS 连接时被中断。**已经成功登录或注册设备，不代表后续每一次 Apple 请求都能连通；这条错误也不能直接证明账号或 App Group 权限有问题。**

修复版对开发者接口的连接失败按 **1、2、4 秒**退避重试，最多共 **4 次尝试**，并设置 15 秒连接超时及 60 秒请求超时。日志会显示重试次数。仅在连接阶段失败时重试；服务器返回的错误、响应读取失败等不会自动重复提交，以免重复执行开发者账户操作。证书校验保持开启。

若重试耗尽仍失败：

1. 检查 **Mac** 的网络，因为签名请求由 Mac 发出。
2. 尝试另一个网络，例如手机热点；使用代理时可切换节点或尝试直连。不要把“必须关闭手机 VPN”当作所有签名错误的通用解法。
3. 保存最新错误的域名、阶段和错误类型。后续如果变成 Apple 返回的业务错误码，应按新错误处理，不再当成 TLS 问题。

本次测试中，改用 macOS TLS 也出现过偶发握手中断，因此最终保留原有 TLS 实现，以有限重试处理这类连接失败。换 TLS 库或关闭证书校验都不能替代网络排查。

### 网络检查通过，但仍不能保证签名成功

无需登录即可检查打包后的程序到 Apple 服务的连接：

```bash
./build/HermesEnabler-Fixed.app/Contents/MacOS/hcli --check-network
```

该检查请求不带账户信息，返回 **HTTP 401 Unauthorized** 仍能证明 TLS 握手完成，不能据此判断密码错误。它不执行 `updateAppId`，也不会证明 App Group、账户权限或最终安装已经成功。单次 `curl` 成功同样不能排除后续连接偶发失败。

### “手表已注册”可能注册的是错误设备

上游旧代码在没有提供 `WATCH_UDID` 时，会使用写死的作者手表标识。因此旧日志中的“手表已注册为开发设备”不能证明注册的是自己的手表。

修复版删除了这个默认值，改为用户明确填写，并在手表注册失败时停止。**不要为了跳过输入，把自己的 UDID 再写回源码作为默认值。**

### Xcode 能看到手机，却看不到手表

本次 `devicectl`、`xctrace` 和 `xcdevice` 最初都只列出 iPhone。通过 Device Hub 的 `Pair Nearby Device…` 完成手表配对后，才读到了真实手表 UDID。先完成发现和配对，再继续签名安装。

### 程序显示完成，却没有装到手表

旧代码会打印部分 `devicectl` 安装错误，随后仍返回成功。修复版在调用失败或返回非零退出码时报告失败；签名产物缺少 `Watch` 目录也会停止。请以手表安装日志及手表上的实际应用为准。

### 重新运行时验证码输入状态不对

修复版在开始新一轮安装时清空验证码状态，并在提交验证码后清理旧提示缓冲，避免上一轮的 `2FA code:` 提示再次触发输入框。

## 已知限制

- 免费签名有有效期，通常为 **7 天**；到期需要重新签名。更新时保持相同 Apple ID 和 Bundle ID。
- 当前 CLI 保留上游的 `MaxCertsBehavior::Revoke`：遇到证书数量上限 `7460` 时可能吊销旧证书，使使用该证书签名的其他应用失效。
- 修改 MobileGestalt 后不要覆盖干净的原始备份。需要还原时使用原始备份；如果表盘修改未生效，按 HermesEnabler 的提示处理或重启手表。
- 此次验证覆盖编译、应用签名校验、17 项回归测试和 Apple 服务连接检查，**不等于已经完成任意用户设备上的端到端签名、安装及表盘修改验证**。

## 开发与验证

```bash
cargo test -p isideload --release --locked --lib
```

默认跳过联网测试。明确需要测试 Apple 服务连接时运行：

```bash
cargo test -p isideload --release --locked --lib \
  check_apple_connection_with_retries -- --ignored --nocapture
```

测试使用合成请求或不带账户信息的连接检查，不需要提交个人设备标识。

```text
src/main.rs          登录、设备注册、签名、安装及网络诊断
gui/main.swift      图形界面与手表 UDID 输入
vendor/isideload/    App Group、签名及连接重试逻辑
scripts/build.sh     构建 HermesEnabler-Fixed.app
scripts/make-dmg.sh  生成修复版 DMG
docs/PATCHES.md      上游补丁说明
```

## 上游与许可

本项目基于 [RyanChanUnknown/hermesenabler-installer](https://github.com/RyanChanUnknown/hermesenabler-installer)。上游补丁包括从 anisette 服务读取匹配的 `client_info`，以及为 Watch 应用关联 App Group，细节见 [docs/PATCHES.md](docs/PATCHES.md)。

相关项目：[HermesEnabler](https://github.com/pookjw/HermesEnabler)、[iloader](https://github.com/nab138/iloader)、[isideload](https://github.com/nab138/isideload)。

MIT，见 [LICENSE](LICENSE)。第三方许可见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。
