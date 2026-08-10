import SwiftUI

// Device picker + download flow. BLE transport lands next milestone; the sheet
// is fully wired to a simulated connection so the UX is testable today.
struct DownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var progress: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Theme.faint).frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
            Text("从潜水电脑下载").font(.system(size: 17, weight: .bold))
            (Text("把潜水电脑调到 ") + Text("Bluetooth").foregroundStyle(Theme.accent).bold()
             + Text(" 模式（Menu → Bluetooth），它就会出现在这里"))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)

            label("我的设备")
            deviceRow(name: "Peregrine", serial: "9D8ACD80",
                      status: "信号 ▂▄▆ · 上次同步 今天", enabled: true)
            deviceRow(name: "Perdix 3", serial: "E7A2C415",
                      status: "未检测到 — 请打开电脑蓝牙", enabled: false)

            label("附近的新设备")
            Text("扫描中… 新的 Shearwater 出现后点击即可配对\n同一潜水如被两台电脑同时记录，会自动识别合并")
                .font(.system(size: 11)).foregroundStyle(Theme.faint)
                .frame(maxWidth: .infinity).padding(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))

            if let progress {
                Text(progress).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(18)
        .background(Theme.panel2)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).kerning(1.5)
            .foregroundStyle(Theme.muted).padding(.top, 4)
    }

    private func deviceRow(name: String, serial: String, status: String, enabled: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: enabled ? "dot.radiowaves.left.and.right" : "moon.zzz")
                .foregroundStyle(enabled ? Theme.accent : Theme.faint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 13.5, weight: .semibold))
                    Text("[\(serial)]").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                Text(status).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if enabled {
                Button("下载") { simulate() }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.abyss)
            }
        }
        .padding(13)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .opacity(enabled ? 1 : 0.45)
    }

    private func simulate() {
        let steps = ["连接 Peregrine…", "读取潜水清单 (47 条)…", "对比本地记录…", "已是最新 ✓"]
        progress = steps[0]
        for (i, s) in steps.enumerated().dropFirst() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 * Double(i)) {
                progress = s
                if i == steps.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
                }
            }
        }
    }
}
