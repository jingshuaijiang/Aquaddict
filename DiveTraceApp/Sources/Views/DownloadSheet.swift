import SwiftUI
import DiveKit

// Real device picker + download flow over CoreBluetooth.
struct DownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiveStore.self) private var store
    @State private var ble = BLEManager()
    @State private var manager = DownloadManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Theme.faint).frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
            Text(loc("从潜水电脑下载", "Download from Dive Computer")).font(.system(size: 17, weight: .bold))
            (Text(loc("把潜水电脑调到 ", "Put your computer in ")) + Text("Bluetooth").foregroundStyle(Theme.accent).bold()
             + Text(loc(" 模式（Menu → Bluetooth），它就会出现在这里", " mode (Menu → Bluetooth) and it will appear here")))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)

            if ble.bluetoothOff {
                Label(loc("蓝牙已关闭 — 请在设置里打开", "Bluetooth is off — enable it in Settings"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Theme.danger)
            }

            label(loc("附近的 Shearwater", "NEARBY SHEARWATER"))
            if ble.devices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text(loc("扫描中…", "Scanning…")).font(.system(size: 12)).foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity).padding(16)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            ForEach(ble.devices) { device in
                deviceRow(device)
            }

            phaseView
            if !BLELog.shared.lines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(BLELog.shared.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }
            Spacer()
        }
        .padding(18)
        .background(Theme.panel2)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { ble.startScan() }
        .onDisappear { ble.stopScan(); ble.disconnect() }
    }

    private var busy: Bool {
        switch manager.phase {
        case .idle, .done, .failed: false
        default: true
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).kerning(1.5)
            .foregroundStyle(Theme.muted).padding(.top, 4)
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).font(.system(size: 13.5, weight: .semibold))
                Text(loc("信号 ", "signal ") + "\(signalBars(device.rssi)) · \(device.model?.displayName ?? "Shearwater")")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(loc("下载", "Get")) {
                Task { await manager.download(from: device, ble: ble, store: store) }
            }
            .disabled(busy)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(busy ? Theme.faint : Theme.accent, in: Capsule())
            .foregroundStyle(Theme.abyss)
        }
        .padding(13)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }

    private func signalBars(_ rssi: Int) -> String {
        rssi > -60 ? "▂▄▆" : rssi > -75 ? "▂▄" : "▂"
    }

    @ViewBuilder
    private var phaseView: some View {
        switch manager.phase {
        case .idle:
            EmptyView()
        case .connecting(let name):
            progressLine(loc("连接 ", "Connecting ") + "\(name)…")
        case .readingManifest:
            progressLine(loc("读取潜水清单…", "Reading dive manifest…"))
        case .downloading(let current, let total):
            VStack(spacing: 6) {
                progressLine(loc("下载潜水 ", "Downloading dive ") + "\(current)/\(total)…")
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .tint(Theme.accent)
            }
        case .done(let new):
            Text(new == 0 ? loc("✓ 已是最新 — 没有新潜水", "✓ Up to date — no new dives")
                          : loc("✓ 下载完成 — ", "✓ Done — ") + "\(new)" + loc(" 潜已加入日志本", " dives added"))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.good)
                .frame(maxWidth: .infinity)
                .task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                }
        case .failed(let message):
            Text(loc("下载失败：", "Download failed: ") + "\(message)")
                .font(.system(size: 11)).foregroundStyle(Theme.danger)
        }
    }

    private func progressLine(_ t: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().tint(Theme.accent)
            Text(t).font(.system(size: 12)).foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
    }
}
