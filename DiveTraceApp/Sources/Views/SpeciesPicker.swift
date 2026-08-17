import SwiftUI

// What did you see on this dive? Emoji quick-grid + your life list + custom.
struct SpeciesPickerSheet: View {
    let diveID: UInt32

    @Environment(\.dismiss) private var dismiss
    @State private var store = SpeciesStore.shared
    @State private var newName = ""

    private var current: [String] { store.species(for: diveID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(loc("常见物种", "COMMON SIGHTINGS"))
                        .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3),
                              spacing: 8) {
                        ForEach(SpeciesStore.presets, id: \.en) { preset in
                            let name = loc(preset.zh, preset.en)
                            let on = current.contains(name)
                            Button {
                                store.toggle(name, for: diveID)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(preset.emoji).font(.system(size: 22))
                                    Text(name).font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(on ? Theme.accent : Theme.line,
                                            lineWidth: on ? 1.5 : 1))
                                .foregroundStyle(on ? Theme.accent : Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField(loc("其他物种…", "Something else…"), text: $newName)
                            .textFieldStyle(.roundedBorder)
                        Button(loc("添加", "Add")) {
                            store.add(newName, for: diveID)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.abyss)
                    }

                    let others = store.lifeList
                        .filter { entry in
                            !SpeciesStore.presets.contains {
                                loc($0.zh, $0.en) == entry.name
                            }
                        }
                    if !others.isEmpty {
                        Text(loc("你的图鉴", "YOUR LIFE LIST"))
                            .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                            .foregroundStyle(Theme.muted)
                        FlowChips(items: others.map(\.name),
                                  selected: Set(current)) { name in
                            store.toggle(name, for: diveID)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.abyss)
            .navigationTitle(loc("这潜看到了什么", "Sightings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("完成", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// simple wrapping chip row
struct FlowChips: View {
    let items: [String]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: 8) {
            ForEach(items, id: \.self) { name in
                Button {
                    toggle(name)
                } label: {
                    Text(name).font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.panel, in: Capsule())
                        .overlay(Capsule().stroke(
                            selected.contains(name) ? Theme.accent : Theme.line,
                            lineWidth: 1))
                        .foregroundStyle(selected.contains(name) ? Theme.accent : Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
