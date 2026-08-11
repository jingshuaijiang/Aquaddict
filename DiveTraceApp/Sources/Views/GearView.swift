import SwiftUI

// Gear management: tank sets, service countdowns, weighting notes.
struct GearView: View {
    @State private var gear = GearStore.shared
    @State private var addingTank = false
    @State private var addingItem = false
    @State private var addingWeight = false

    var body: some View {
        List {
            tankSection
            serviceSection
            weightSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.abyss)
        .navigationTitle(loc("装备管理", "Gear"))
        .sheet(isPresented: $addingTank) { TankForm() }
        .sheet(isPresented: $addingItem) { GearItemForm() }
        .sheet(isPresented: $addingWeight) { WeightForm() }
    }

    // MARK: tanks

    private var tankSection: some View {
        Section {
            ForEach(gear.tanks) { tank in
                Button {
                    gear.setDefaultTank(tank.id)
                } label: {
                    HStack {
                        Image(systemName: tank.isDefault ? "star.fill" : "star")
                            .foregroundStyle(tank.isDefault ? Theme.accent : Theme.faint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tank.name).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(String(format: "%.1f L · ", tank.volumeL)
                                 + U.pressure(tank.fillBar) + " · "
                                 + U.tankCapacity(volumeL: tank.volumeL, fillBar: tank.fillBar))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if tank.isDefault {
                            Text(loc("RMV 计算用", "Used for RMV"))
                                .font(.system(size: 10)).foregroundStyle(Theme.accent)
                        }
                    }
                }
                .swipeActions {
                    Button(loc("删除", "Delete"), role: .destructive) {
                        gear.deleteTank(tank.id)
                    }
                }
            }
            Button {
                addingTank = true
            } label: {
                Label(loc("添加瓶组", "Add tank set"), systemImage: "plus.circle")
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text(loc("瓶组", "TANK SETS"))
        } footer: {
            Text(loc("⭐ 标记的瓶组用于计算 RMV（不再假设 AL80）",
                     "⭐ default tank drives RMV instead of the AL80 assumption"))
        }
        .listRowBackground(Theme.panel)
    }

    // MARK: serviceable gear

    private var serviceSection: some View {
        Section {
            ForEach(gear.items) { item in
                NavigationLink(destination: GearItemDetailView(itemID: item.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 14, weight: .semibold))
                            Text(item.category
                                 + ((item.parts?.isEmpty ?? true) ? ""
                                    : loc(" · \(item.parts!.count) 个部件",
                                          " · \(item.parts!.count) parts")))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if let days = item.worstDays {
                            Text(days >= 0
                                 ? loc("还有 \(days) 天", "\(days)d left")
                                 : loc("过期 \(-days) 天", "\(-days)d overdue"))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(days > 30 ? Theme.good
                                                 : days >= 0 ? Theme.temp : Theme.danger)
                        }
                    }
                }
                .swipeActions {
                    Button(loc("删除", "Delete"), role: .destructive) {
                        gear.deleteItem(item.id)
                    }
                }
            }
            Button {
                addingItem = true
            } label: {
                Label(loc("添加装备", "Add gear"), systemImage: "plus.circle")
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text(loc("装备保养", "SERVICE"))
        } footer: {
            Text(loc("点进装备可管理部件（干衣的颈封/手封/拉链/阀门各自跟踪）",
                     "Open an item to manage parts (drysuit seals/zipper/valves tracked separately)"))
        }
        .listRowBackground(Theme.panel)
    }

    // MARK: weights

    private var weightSection: some View {
        Section(loc("配重记录", "WEIGHTING")) {
            ForEach(gear.weights) { w in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.suit).font(.system(size: 14, weight: .semibold))
                        Text((w.saltWater ? loc("海水", "Salt") : loc("淡水", "Fresh"))
                             + (w.note.isEmpty ? "" : " · \(w.note)"))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(String(format: "%.1f kg", w.weightKg))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
                .swipeActions {
                    Button(loc("删除", "Delete"), role: .destructive) {
                        gear.deleteWeight(w.id)
                    }
                }
            }
            Button {
                addingWeight = true
            } label: {
                Label(loc("添加配重记录", "Add weighting note"), systemImage: "plus.circle")
                    .foregroundStyle(Theme.accent)
            }
        }
        .listRowBackground(Theme.panel)
    }
}

// MARK: - forms

struct TankForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var volume = 12.9
    @State private var fill = 237.0

    var body: some View {
        NavigationStack {
            Form {
                Menu {
                    ForEach(TankPreset.all, id: \.name) { preset in
                        Button("\(preset.name) · " + U.tankCapacity(volumeL: preset.volumeL,
                                                                    fillBar: preset.fillBar)) {
                            name = preset.name
                            volume = preset.volumeL
                            fill = preset.fillBar
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.circle")
                        Text(loc("选择常见瓶组（HP100 / LP85 / AL80…）",
                                 "Pick a common tank (HP100 / LP85 / AL80…)"))
                        Spacer()
                    }
                    .foregroundStyle(Theme.accent)
                }
                TextField(loc("名称", "Name"), text: $name)
                Stepper(String(format: loc("水容积 %.1f L", "Water volume %.1f L"), volume),
                        value: $volume, in: 3 ... 40, step: 0.1)
                Stepper(loc("常用充压 ", "Usual fill ") + U.pressure(fill),
                        value: $fill, in: 100 ... 300, step: 1)
                LabeledContent(loc("气容量", "Gas capacity"),
                               value: U.tankCapacity(volumeL: volume, fillBar: fill))
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(loc("新瓶组", "New Tank Set"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("保存", "Save")) {
                        GearStore.shared.addTank(name: name, volumeL: volume, fillBar: fill)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct GearItemForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var tracksService = true
    @State private var lastService = Date()
    @State private var intervalMonths = 12

    private let categories = [
        loc("调节器", "Regulator"), loc("BCD/背飞", "BCD/Wing"),
        loc("干衣", "Drysuit"), loc("湿衣", "Wetsuit"),
        loc("电脑", "Computer"), loc("灯", "Light"), loc("其他", "Other"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField(loc("名称", "Name"), text: $name)
                Picker(loc("类别", "Category"), selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                Toggle(loc("跟踪保养周期", "Track service"), isOn: $tracksService)
                if tracksService {
                    DatePicker(loc("上次保养", "Last serviced"),
                               selection: $lastService, displayedComponents: .date)
                    Stepper(loc("周期 \(intervalMonths) 个月", "Every \(intervalMonths) months"),
                            value: $intervalMonths, in: 1 ... 60)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(loc("新装备", "New Gear"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("保存", "Save")) {
                        GearStore.shared.addItem(
                            name: name,
                            category: category.isEmpty ? categories[0] : category,
                            lastService: tracksService ? lastService : nil,
                            intervalMonths: tracksService ? intervalMonths : nil)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { if category.isEmpty { category = categories[0] } }
    }
}

struct WeightForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var suit = ""
    @State private var salt = true
    @State private var kg = 4.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(loc("暴露服（如 5mm 湿衣）", "Exposure suit (e.g. 5mm wetsuit)"),
                          text: $suit)
                Picker(loc("水域", "Water"), selection: $salt) {
                    Text(loc("海水", "Salt")).tag(true)
                    Text(loc("淡水", "Fresh")).tag(false)
                }
                .pickerStyle(.segmented)
                Stepper(String(format: loc("配重 %.1f kg", "Weight %.1f kg"), kg),
                        value: $kg, in: 0 ... 20, step: 0.5)
                TextField(loc("备注（瓶组、体感…）", "Note (tanks, feel…)"), text: $note)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(loc("配重记录", "Weighting Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("保存", "Save")) {
                        GearStore.shared.addWeight(suit: suit, saltWater: salt,
                                                   weightKg: kg, note: note)
                        dismiss()
                    }
                    .disabled(suit.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// One gear item: its own service cycle plus independently tracked parts.
struct GearItemDetailView: View {
    let itemID: UUID
    @State private var gear = GearStore.shared
    @State private var addingPart = false

    private var item: GearItem? { gear.item(itemID) }
    private var isDrysuit: Bool {
        [loc("干衣", "Drysuit"), "Drysuit", "干衣"].contains(item?.category ?? "")
    }

    var body: some View {
        List {
            if let item {
                Section(loc("整体", "OVERALL")) {
                    countdownRow(name: loc("整体保养", "Full service"),
                                 days: item.daysToService) {
                        gear.markServiced(item.id)
                    }
                }
                .listRowBackground(Theme.panel)

                Section(loc("部件", "PARTS")) {
                    ForEach(item.parts ?? []) { part in
                        countdownRow(name: part.name, days: part.daysToService,
                                     sub: loc("每 \(part.intervalMonths) 个月",
                                              "every \(part.intervalMonths) mo")) {
                            gear.markPartServiced(itemID: item.id, partID: part.id)
                        }
                        .swipeActions {
                            Button(loc("删除", "Delete"), role: .destructive) {
                                gear.deletePart(itemID: item.id, partID: part.id)
                            }
                        }
                    }
                    if isDrysuit, (item.parts ?? []).isEmpty {
                        Button {
                            gear.addDrysuitTemplate(to: item.id)
                        } label: {
                            Label(loc("一键添加干衣部件（颈封/手封/拉链/阀门）",
                                      "Add drysuit parts (seals/zipper/valves)"),
                                  systemImage: "wand.and.stars")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Button {
                        addingPart = true
                    } label: {
                        Label(loc("添加部件", "Add part"), systemImage: "plus.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .listRowBackground(Theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.abyss)
        .navigationTitle(item?.name ?? "")
        .sheet(isPresented: $addingPart) {
            PartForm(itemID: itemID)
        }
    }

    private func countdownRow(name: String, days: Int?, sub: String? = nil,
                              serviced: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold))
                if let sub {
                    Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if let days {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(days >= 0
                         ? loc("还有 \(days) 天", "\(days) days left")
                         : loc("过期 \(-days) 天", "\(-days) days overdue"))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(days > 30 ? Theme.good
                                         : days >= 0 ? Theme.temp : Theme.danger)
                    Button(loc("已保养", "Serviced")) { serviced() }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
            } else {
                Text(loc("未跟踪", "Untracked")).font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

struct PartForm: View {
    let itemID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var months = 12
    @State private var last = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField(loc("部件名（如 颈封）", "Part name (e.g. neck seal)"), text: $name)
                Stepper(loc("周期 \(months) 个月", "Every \(months) months"),
                        value: $months, in: 1 ... 60)
                DatePicker(loc("上次保养/更换", "Last serviced/replaced"),
                           selection: $last, displayedComponents: .date)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(loc("新部件", "New Part"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("保存", "Save")) {
                        GearStore.shared.addPart(to: itemID, name: name,
                                                 intervalMonths: months, lastService: last)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
