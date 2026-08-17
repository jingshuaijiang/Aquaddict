import SwiftUI
import DiveKit

// Interactive trim simulator: a side-view diver whose equilibrium pitch is
// solved from the rig's mass/buoyancy distribution. Landscape-only (rotated
// in portrait), opened from the drawer.
struct TrimSimulatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var tankShiftCm = 0.0
    @State private var tankHeavy = 5.0
    @State private var weightKg = 4.0
    @State private var weightXCm = -5.0
    @State private var wingL = 3.0
    @State private var suitL = 4.0
    @State private var lungL = 0.0
    @State private var postureDeg = 0.0

    private var rig: TrimModel.Rig {
        TrimModel.Rig(tankShiftM: tankShiftCm / 100, tankHeavyKg: tankHeavy,
                      weightKg: weightKg, weightX: weightXCm / 100,
                      wingLiftL: wingL, suitGasL: suitL, lungL: lungL)
    }

    private var result: TrimResult {
        TrimModel.solve(rig: rig, postureDeg: postureDeg)
    }

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            let w = max(geo.size.width, geo.size.height)
            let h = min(geo.size.width, geo.size.height)
            ZStack {
                Theme.abyss.ignoresSafeArea()
                content(width: w, height: h)
                    .frame(width: w, height: h)
                    .rotationEffect(portrait ? .degrees(90) : .zero)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Theme.abyss)
        .foregroundStyle(Theme.ink)
        .statusBarHidden()
    }

    private func content(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            scene
                .frame(width: width * 0.56)
            controls
                .frame(width: width * 0.44)
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(9)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(14)
        }
    }

    // MARK: scene

    private var scene: some View {
        let r = result
        return VStack(spacing: 6) {
            HStack(spacing: 14) {
                chip(loc("Trim 角", "Trim"),
                     String(format: "%+.0f°", r.angleDeg),
                     color: abs(r.angleDeg) < 8 ? Theme.good
                            : abs(r.angleDeg) < 20 ? Theme.temp : Theme.danger)
                chip(loc("净浮力", "Buoyancy"),
                     String(format: "%+.1f kg", r.netBuoyancyKg),
                     color: abs(r.netBuoyancyKg) < 1 ? Theme.good : Theme.temp)
            }
            .padding(.top, 12)
            DiverScene(result: r, rig: rig)
                .animation(.spring(duration: 0.5), value: r.angleDeg)
            Text(coaching(r))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(height: 44)
                .padding(.horizontal, 18)
        }
    }

    private func chip(_ k: String, _ v: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.system(size: 10)).foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    private func coaching(_ r: TrimResult) -> String {
        if r.angleDeg < -12 {
            return loc("头重：重心跑到浮心前面了 — valve drill 时瓶带前滑就是这个感觉。把瓶带后移或配重后挪。",
                       "Head-heavy: CG moved ahead of CB — a slipped tank band in a valve drill feels exactly like this. Shift the tank or weights back.")
        }
        if r.angleDeg > 12, suitL > 5 {
            return loc("气体跑向胸和头，越抬越翘 — 这就是'抬头容易失控上浮'的正反馈。先压平姿态、排干衣气。",
                       "Gas migrated to your chest and head, amplifying the tilt — the head-up runaway. Flatten out and vent the suit.")
        }
        if r.angleDeg > 12 {
            return loc("脚重头高：配重太靠脚，或瓶带太靠后。",
                       "Feet-heavy: weights too far toward the feet, or the tank too far back.")
        }
        if r.netBuoyancyKg > 1.5 {
            return loc("正浮力偏大 — 会上浮，排一点 wing/干衣。",
                       "Positively buoyant — you'll rise. Vent a little.")
        }
        if r.netBuoyancyKg < -1.5 {
            return loc("负浮力偏大 — 在下沉，补一点气。",
                       "Negatively buoyant — you're sinking. Add a little gas.")
        }
        return loc("水平 · 中性 — 教科书 trim。红点 = 重心 CG，青点 = 浮心 CB：CB 正压在 CG 上方就是稳定。",
                   "Flat and neutral — textbook trim. Red = CG, cyan = CB: stable when CB sits directly above CG.")
    }

    // MARK: controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                presets
                slider(loc("姿态（抬头 + / 低头 −）", "Posture (head up + / down −)"),
                       value: $postureDeg, range: -15 ... 15, step: 1, unit: "°")
                slider(loc("瓶带位置（向头 +）", "Tank band (toward head +)"),
                       value: $tankShiftCm, range: -10 ... 10, step: 1, unit: "cm")
                slider(loc("瓶在水中重（满5 → 空1）", "Tank weight (full 5 → empty 1)"),
                       value: $tankHeavy, range: 1 ... 6, step: 0.5, unit: "kg")
                slider(loc("配重量", "Weights"),
                       value: $weightKg, range: 0 ... 8, step: 0.5, unit: "kg")
                slider(loc("配重位置（向头 +）", "Weight position (toward head +)"),
                       value: $weightXCm, range: -45 ... 25, step: 5, unit: "cm")
                slider("Wing", value: $wingL, range: 0 ... 10, step: 0.5, unit: "L")
                slider(loc("干衣气", "Drysuit gas"),
                       value: $suitL, range: 0 ... 10, step: 0.5, unit: "L")
                slider(loc("肺（吸满 + / 呼尽 −）", "Lungs (full + / empty −)"),
                       value: $lungL, range: -2 ... 2, step: 0.5, unit: "L")
            }
            .padding(EdgeInsets(top: 14, leading: 6, bottom: 20, trailing: 18))
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                preset(loc("标准", "Baseline")) {
                    (tankShiftCm, tankHeavy, weightKg, weightXCm) = (0, 5, 4, -5)
                    (wingL, suitL, lungL, postureDeg) = (3, 4, 0, 0)
                }
                preset("Valve drill") {
                    tankShiftCm = 8
                    postureDeg = 0
                }
                preset(loc("抬头看队友", "Looking up")) {
                    postureDeg = 12
                    suitL = max(suitL, 6)
                }
                preset(loc("新手脚重", "Feet-heavy newbie")) {
                    weightXCm = -35
                    suitL = 2
                    postureDeg = 0
                }
                preset(loc("瓶快空了", "Near-empty tank")) {
                    tankHeavy = 1
                }
            }
        }
    }

    private func preset(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.panel2, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Text(String(format: "%+.1f %@", value.wrappedValue, unit))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            Slider(value: value, in: range, step: step).tint(Theme.accent)
        }
    }
}

// The side-view diver, drawn in body coordinates and rotated to the solved pitch.
private struct DiverScene: View {
    let result: TrimResult
    let rig: TrimModel.Rig

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
            let scale = min(size.width, size.height * 2) * 0.42  // px per meter
            let theta = -result.angleDeg * .pi / 180             // screen y is down

            // water: surface shimmer at the top
            let surface = Path(CGRect(x: 0, y: 0, width: size.width, height: 5))
            ctx.fill(surface, with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.5), .clear]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: 26)))

            // body frame (x head, y up) → screen, rotated by the solved pitch
            func world(_ x: Double, _ y: Double) -> CGPoint {
                let px = x * cos(theta) - (-y) * sin(theta)
                let py = x * sin(theta) + (-y) * cos(theta)
                return CGPoint(x: center.x + px * scale, y: center.y + py * scale)
            }

            func capsule(from a: (Double, Double), to b: (Double, Double),
                         width: Double, color: Color) {
                let pa = world(a.0, a.1)
                let pb = world(b.0, b.1)
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: width * scale,
                                              lineCap: .round))
            }

            // tank (behind the body)
            let tx = 0.02 + rig.tankShiftM
            capsule(from: (tx - 0.26, 0.14), to: (tx + 0.26, 0.14),
                    width: 0.14, color: Theme.panel2)
            ctx.fill(Path(ellipseIn: CGRect(origin: world(tx + 0.30, 0.14), size: .zero)
                        .insetBy(dx: -0.03 * scale, dy: -0.03 * scale)),
                     with: .color(Theme.faint))   // valve

            // wing bladder
            if rig.wingLiftL > 0.2 {
                let r = 0.05 + rig.wingLiftL * 0.006
                ctx.fill(Path(ellipseIn: CGRect(origin: world(-0.02, 0.10), size: .zero)
                            .insetBy(dx: -(0.20 * scale), dy: -(r * scale))),
                         with: .color(Theme.depth.opacity(0.45)))
            }

            // body
            capsule(from: (-0.32, 0), to: (0.34, 0), width: 0.20, color: Theme.depth)
            // head
            ctx.fill(Path(ellipseIn: CGRect(origin: world(0.52, 0.03), size: .zero)
                        .insetBy(dx: -0.095 * scale, dy: -0.095 * scale)),
                     with: .color(Theme.depth))
            // arms reaching forward
            capsule(from: (0.28, -0.07), to: (0.58, -0.09), width: 0.06,
                    color: Theme.depth)
            // thighs + shins (frog-kick bend: shins angle up)
            capsule(from: (-0.32, 0), to: (-0.60, -0.01), width: 0.11, color: Theme.depth)
            capsule(from: (-0.60, -0.01), to: (-0.80, 0.10), width: 0.07, color: Theme.depth)
            // fins
            capsule(from: (-0.80, 0.10), to: (-0.97, 0.16), width: 0.045,
                    color: Theme.accent.opacity(0.8))

            // weights block
            capsule(from: (rig.weightX - 0.06, -0.11), to: (rig.weightX + 0.06, -0.11),
                    width: 0.07, color: Color.black.opacity(0.85))

            // drysuit bubble at its migrated position
            if rig.suitGasL > 0.2 {
                let r = 0.03 + 0.012 * rig.suitGasL
                ctx.fill(Path(ellipseIn: CGRect(origin: world(result.suitBubbleX, 0.075),
                                                size: .zero)
                            .insetBy(dx: -(r * 1.6 * scale), dy: -(r * scale))),
                         with: .color(Theme.accent.opacity(0.35)))
            }

            // CG (red) and CB (cyan) with plumb lines
            let cg = world(result.cgX, result.cgY)
            let cb = world(result.cbX, result.cbY)
            var plumb = Path()
            plumb.move(to: CGPoint(x: cb.x, y: cb.y - 0.25 * scale))
            plumb.addLine(to: CGPoint(x: cg.x, y: cg.y + 0.25 * scale))
            ctx.stroke(plumb, with: .color(Theme.ink.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ctx.fill(Path(ellipseIn: CGRect(origin: cg, size: .zero)
                        .insetBy(dx: -5, dy: -5)), with: .color(Theme.danger))
            ctx.fill(Path(ellipseIn: CGRect(origin: cb, size: .zero)
                        .insetBy(dx: -5, dy: -5)), with: .color(Theme.accent))

            // net buoyancy arrow at the right edge
            let net = result.netBuoyancyKg
            if abs(net) > 0.3 {
                let ax = size.width - 30
                let len = min(abs(net) * 14, 60.0)
                var arrow = Path()
                arrow.move(to: CGPoint(x: ax, y: center.y + (net > 0 ? len : -len) / 2))
                arrow.addLine(to: CGPoint(x: ax, y: center.y - (net > 0 ? len : -len) / 2))
                ctx.stroke(arrow, with: .color(net > 0 ? Theme.good : Theme.danger),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let tipY = center.y - (net > 0 ? len : -len) / 2
                var tip = Path()
                tip.move(to: CGPoint(x: ax - 5, y: tipY + (net > 0 ? 7 : -7)))
                tip.addLine(to: CGPoint(x: ax, y: tipY))
                tip.addLine(to: CGPoint(x: ax + 5, y: tipY + (net > 0 ? 7 : -7)))
                ctx.stroke(tip, with: .color(net > 0 ? Theme.good : Theme.danger),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}
