import Cocoa
import SwiftUI

// MARK: - 运行器

final class Runner: ObservableObject {
    @Published var log: String = ""
    @Published var running: Bool = false
    @Published var need2FA: Bool = false
    @Published var twoFA: String = ""
    @Published var finished: Bool = false
    @Published var ok: Bool = false

    private var proc: Process?
    private var stdinHandle: FileHandle?
    private var buffer: String = ""

    let hcliPath: String

    init() {
        // 可执行文件放在 .app 同级目录，或工程里的 release 路径
        // 分发包里 hcli 与 GUI 同在 Contents/MacOS；开发时回退到工程路径。
        let macosDir = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
        let candidates = [
            macosDir.appendingPathComponent("hcli").path,
            "/usr/local/bin/hcli",
            "/opt/homebrew/bin/hcli"
        ]
        hcliPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[2]
    }

    func start(email: String, password: String, ipa: String, udid: String, watchUDID: String) {
        guard !running else { return }
        running = true
        finished = false
        ok = false
        log = ""
        buffer = ""
        need2FA = false
        twoFA = ""

        let p = Process()
        p.executableURL = URL(fileURLWithPath: hcliPath)
        p.arguments = [ipa, udid]

        var env = ProcessInfo.processInfo.environment
        env["APPLE_ID"] = email
        env["APPLE_PASSWORD"] = password
        env["ANISETTE_URL"] = "https://ani.stikstore.app"
        env["WATCH_UDID"] = watchUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let outPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        p.standardInput = inPipe
        self.stdinHandle = inPipe.fileHandleForWriting

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.ingest(s) }
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false
                self.finished = true
                self.ok = (proc.terminationStatus == 0)
                self.log += "\n—— 进程结束，退出码 \(proc.terminationStatus) ——\n"
                outPipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        do {
            try p.run()
            self.proc = p
        } catch {
            log += "启动失败: \(error.localizedDescription)\n"
            running = false
        }
    }

    private func ingest(_ s: String) {
        log += s
        buffer += s
        if !need2FA, buffer.contains("2FA code:") || buffer.contains("2FA") {
            if buffer.contains("2FA code:") { need2FA = true }
        }
        if buffer.count > 6000 { buffer = String(buffer.suffix(3000)) }
    }

    func submit2FA() {
        guard let h = stdinHandle else { return }
        let line = twoFA.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        if let d = line.data(using: .utf8) { try? h.write(contentsOf: d) }
        need2FA = false
        twoFA = ""
        buffer = ""
    }

    func abort() {
        proc?.terminate()
    }
}

// MARK: - 界面

struct ContentView: View {
    @StateObject private var runner = Runner()

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var ipa: String = ContentView.defaultIPA()
    @State private var udid: String = ""
    @State private var watchUDID: String = ""
    @State private var showAbout = false

    static func defaultIPA() -> String {
        let home = NSHomeDirectory()
        let candidates = [
            home + "/Downloads/HermesEnabler.ipa",
            home + "/Desktop/HermesEnabler.ipa",
            home + "/Downloads/HermesEnabler 2.ipa"
        ]
        // 找不到就留空，由占位符提示，避免在界面上暴露用户目录
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? ""
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    labeled("Apple ID") {
                        TextField("you@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeled("密码") {
                        SecureField("Apple ID 密码", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeled("IPA") {
                        HStack {
                            TextField("HermesEnabler.ipa", text: $ipa)
                                .textFieldStyle(.roundedBorder)
                            Button("选择…") { pickIPA() }
                        }
                    }
                    labeled("设备 UDID") {
                        TextField("留空则自动选择第一台已连接设备", text: $udid)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeled("手表 UDID") {
                        TextField("填写自己的 Apple Watch UDID（Xcode 设备窗口可查看）", text: $watchUDID)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(6)
            }

            if runner.need2FA {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("输入手机上收到的 6 位验证码")
                            .font(.headline)
                        HStack {
                            TextField("123456", text: $runner.twoFA)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { runner.submit2FA() }
                            Button("提交") { runner.submit2FA() }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(6)
                }
            }

            HStack(spacing: 10) {
                Button(action: startInstall) {
                    Label("开始安装", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(runner.running || email.isEmpty || password.isEmpty || watchUDID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("中止") { runner.abort() }
                    .controlSize(.large)
                    .disabled(!runner.running)
            }

            if runner.running {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            ConsoleView(text: runner.log)
                .frame(minHeight: 260)

            footer
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 760)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("HermesEnabler 安装器 · 修复版")
                    .font(.title2).bold()
                Text("Apple ID 免费签名 · 含 Watch app 与 App Group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("关于与本软件的开源许可")
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(runner.running ? Color.orange : (runner.finished ? (runner.ok ? Color.green : Color.red) : Color.gray))
                .frame(width: 8, height: 8)
            Text(runner.running ? "运行中…" : (runner.finished ? (runner.ok ? "完成" : "失败，看下面日志") : "待启动"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("v1.0.1 本地修复版 · MIT")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .frame(width: 78, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func pickIPA() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { ipa = url.path }
    }

    private func startInstall() {
        runner.start(email: email, password: password, ipa: ipa, udid: udid, watchUDID: watchUDID)
    }
}

struct ConsoleView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = .textColor
        tv.backgroundColor = .textBackgroundColor
        tv.autoresizingMask = [.width]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            tv.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - 启动

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: ContentView())
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HermesEnabler 安装器"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()


// MARK: - 关于 / 开源许可

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let text = """
    HermesEnabler 安装器
    ────────────────────────────
    一个 macOS 图形前端：用 Apple ID 免费签名，把 HermesEnabler 及其
    Watch App 安装到 iPhone / Apple Watch，并为 Watch App 申请 App Group。

    本软件不包含、也不分发 HermesEnabler 的 IPA。请从上游项目的
    Releases 页面自行下载：
    https://github.com/pookjw/HermesEnabler

    ── 本软件用到的开源项目 ──

    HermesEnabler
      MIT License · Copyright (c) 2026 Jinwoo Kim
      https://github.com/pookjw/HermesEnabler

    iloader
      MIT License · Copyright (c) 2025 nab138
      https://github.com/nab138/iloader

    isideload
      MIT License · Copyright (c) 2025 nab138
      https://github.com/nab138/isideload

    idevice / apple-codesign / reqwest / rustls / tokio
      MIT 或 Apache-2.0（详见随包 THIRD_PARTY_LICENSES.md）

    ── MIT 许可声明 ──

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
    BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

    ── 免责 ──
    修改 MobileGestalt 属于非官方操作，可能导致设备异常。使用风险
    自负。本软件与 Apple Inc. 无任何关联。
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}
