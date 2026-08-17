import SwiftUI
import DiveKit

// Ballast transfer calculator: anchor on one measured config, predict lead
// for another. Standalone module in the drawer.
struct WeightCalcView: View {
    @State private var prefs = Prefs.shared

    // reference (measured) config
    @AppStorage("wcRefTank") private var refTank = "AL80"
    @AppStorage("wcRefPlate") private var refPlate = "steel"
    @AppStorage("wcRefSuit") private var refSuit = "dry200"
    @AppStorage("wcRefSalt") private var refSalt = true
    @AppStorage("wcRefWeight") private var refWeightKg = 12.7
    @AppStorage("wcBody") private var bodyKg = 75.0

    // target config
    @AppStorage("wcTgtTank") private var tgtTank = "2xHP100"
    @AppStorage("wcTgtPlate") private var tgtPlate = "steel"
    @AppStorage("wcTgtSuit") private var tgtSuit = "dry200"
    @AppStorage("wcTgtSalt") private var tgtSalt = false
    @AppStorage("wcCorrection") private var correctionKg = 0.0
    @AppStorage("wcAnchors") private var anchorsJSON = "[]"

    struct Anchor: Codable, Identifiable {
        var id: UUID = UUID()
        var tank: String
        var plate: String
        var suit: String
        var salt: Bool
        var weightKg: Double
    }

    private var anchors: [Anchor] {
        (try? JSONDecoder().decode([Anchor].self, from: Data(anchorsJSON.utf8))) ?? []
    }

    private func saveAnchors(_ a: [Anchor]) {
        if let d = try? JSONEncoder().encode(a) {
            anchorsJSON = String(data: d, encoding: .utf8) ?? "[]"
        }
    }

    static let suits: [(key: String, zh: String, en: String, suit: WeightCalc.Suit)] = [
        ("dry150", "干衣 150g 内衬", "Drysuit 150g", .drysuit(undergarmentGrams: 150)),
        ("dry200", "干衣 200g 内衬", "Drysuit 200g", .drysuit(undergarmentGrams: 200)),
        ("dry300", "干衣 300g 内衬", "Drysuit 300g", .drysuit(undergarmentGrams: 300)),
        ("dry400", "干衣 400g 内衬", "Drysuit 400g", .drysuit(undergarmentGrams: 400)),
        ("wet3", "3mm 湿衣", "3mm wetsuit", .wetsuit(mm: 3)),
        ("wet5", "5mm 湿衣", "5mm wetsuit", .wetsuit(mm: 5)),
        ("wet7", "7mm 湿衣", "7mm wetsuit", .wetsuit(mm: 7)),
        ("skin", "无/水母衣", "None/skin", .none),
    ]

    private func suit(_ key: String) -> WeightCalc.Suit {
        Self.suits.first { $0.key == key }?.suit ?? .none
    }

    private var result: WeightCalc.Breakdown {
        WeightCalc.transfer(
            referenceWeightKg: refWeightKg, bodyKg: bodyKg,
            ref: WeightCalc.Config(tankKey: refTank,
                                   plate: WeightCalc.Plate(rawValue: refPlate) ?? .steel,
                                   suit: suit(refSuit), saltWater: refSalt),
            target: WeightCalc.Config(tankKey: tgtTank,
                                      plate: WeightCalc.Plate(rawValue: tgtPlate) ?? .steel,
                                      suit: suit(tgtSuit), saltWater: tgtSalt),
            correctionKg: correctionKg)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                configCard(title: loc("① 已知配置（实测过的）", "① Known config (measured)"),
                           tank: $refTank, plate: $refPlate,
                           suitKey: $refSuit, salt: $refSalt)
                measuredCard
                anchorsCard
                configCard(title: loc("② 目标配置", "② Target config"),
                           tank: $tgtTank, plate: $tgtPlate,
                           suitKey: $tgtSuit, salt: $tgtSalt)
                resultCard
                Text(loc("估算值（各项 ±0.5 kg）— 换配置后务必在 3 米做空瓶配重检查",
                         "Estimates (±0.5 kg per item) — always verify with an empty-tank weight check at 3 m"))
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("配重换算", "Weight Transfer"))
    }

    // MARK: cards

    private func configCard(title: String, tank: Binding<String>,
                            plate: Binding<String>, suitKey: Binding<String>,
                            salt: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
            HStack(spacing: 10) {
                menuPicker(loc("瓶组", "Tank"), selection: tank,
                           options: WeightCalc.tanks.map { ($0.key, tankLabel($0.key)) })
                menuPicker(loc("背板", "Plate"), selection: plate, options: [
                    ("steel", loc("钢板", "Steel")),
                    ("aluminum", loc("铝板", "Alu")),
                    ("soft", loc("软背/无", "Soft/none")),
                ])
            }
            HStack(spacing: 10) {
                menuPicker(loc("暴露服", "Suit"), selection: suitKey,
                           options: Self.suits.map { ($0.key, loc($0.zh, $0.en)) })
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc("水域", "Water")).font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Picker("", selection: salt) {
                        Text(loc("海水", "Salt")).tag(true)
                        Text(loc("淡水", "Fresh")).tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .cardStyle()
    }

    private func tankLabel(_ key: String) -> String {
        key.hasPrefix("2x") ? loc("双瓶 ", "Double ") + key.dropFirst(2) : key
    }

    private func menuPicker(_ label: String, selection: Binding<String>,
                            options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Menu {
                ForEach(options, id: \.0) { opt in
                    Button(opt.1) { selection.wrappedValue = opt.0 }
                }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection.wrappedValue }?.1 ?? "?")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measuredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc("该配置实测配重", "Measured lead in config ①"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text(weightText(refWeightKg))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
            }
            Slider(value: $refWeightKg, in: 0 ... 20, step: 0.25).tint(Theme.accent)
            HStack {
                Text(loc("体重", "Body weight"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text(String(format: prefs.imperial ? "%.0f lb" : "%.0f kg",
                            prefs.imperial ? bodyKg * 2.2046 : bodyKg))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            Slider(value: $bodyKg, in: 40 ... 130, step: 1).tint(Theme.accent)
            HStack {
                Text(loc("个人修正（按验证结果微调）", "Personal correction"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text(String(format: "%+.1f kg", correctionKg))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(abs(correctionKg) < 0.1 ? Theme.faint : Theme.accent)
            }
            Slider(value: $correctionKg, in: -5 ... 5, step: 0.25).tint(Theme.accent)
        }
        .cardStyle()
    }

    // Verified real-world measurements, loadable as the reference in one tap.
    private var anchorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc("实测锚点库", "VERIFIED ANCHORS"))
                    .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    var a = anchors
                    a.append(Anchor(tank: refTank, plate: refPlate, suit: refSuit,
                                    salt: refSalt, weightKg: refWeightKg))
                    saveAnchors(a)
                } label: {
                    Label(loc("存入当前①", "Save ①"), systemImage: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            if anchors.isEmpty {
                Text(loc("每做一次配重检查就存一个锚点 — 换算基准越多越准",
                         "Save an anchor after every weight check — more anchors, better predictions"))
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            ForEach(anchors) { anchor in
                HStack(spacing: 8) {
                    Image(systemName: "pin")
                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Text("\(tankLabel(anchor.tank)) · "
                         + (Self.suits.first { $0.key == anchor.suit }
                            .map { loc($0.zh, $0.en) } ?? "?")
                         + " · " + (anchor.salt ? loc("海水", "salt") : loc("淡水", "fresh")))
                        .font(.system(size: 11)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Text(weightText(anchor.weightKg))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                    Button {
                        refTank = anchor.tank
                        refPlate = anchor.plate
                        refSuit = anchor.suit
                        refSalt = anchor.salt
                        refWeightKg = anchor.weightKg
                    } label: {
                        Text(loc("设为①", "Use"))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.panel2, in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    Button {
                        saveAnchors(anchors.filter { $0.id != anchor.id })
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13)).foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private var resultCard: some View {
        let r = result
        return VStack(spacing: 12) {
            Text(loc("目标配置预测配重", "Predicted lead for config ②"))
                .font(.system(size: 11, weight: .semibold)).kerning(1)
                .foregroundStyle(Theme.muted)
            Text(weightText(r.targetKg))
                .font(.system(size: 42, weight: .black, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(prefs.imperial
                 ? String(format: "= %.1f kg", r.targetKg)
                 : String(format: "= %.1f lb", r.targetKg * 2.2046))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.muted)
            VStack(spacing: 0) {
                deltaRow(loc("瓶组差异", "Tanks"), r.tankDeltaKg)
                deltaRow(loc("背板差异", "Plate"), r.plateDeltaKg)
                deltaRow(loc("保暖差异", "Insulation"), r.suitDeltaKg)
                deltaRow(loc("水密度", "Water density"), r.waterDeltaKg,
                         last: abs(correctionKg) < 0.1)
                if abs(correctionKg) >= 0.1 {
                    deltaRow(loc("个人修正", "Personal correction"), correctionKg, last: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func deltaRow(_ k: String, _ v: Double, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(k).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text(abs(v) < 0.05 ? "—" : String(format: "%+.1f kg", v))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(abs(v) < 0.05 ? Theme.faint
                                     : v > 0 ? Theme.temp : Theme.good)
            }
            .padding(.vertical, 8)
            if !last { Divider().overlay(Theme.line) }
        }
    }

    private func weightText(_ kg: Double) -> String {
        prefs.imperial ? String(format: "%.0f lb", kg * 2.2046)
                       : String(format: "%.1f kg", kg)
    }
}
