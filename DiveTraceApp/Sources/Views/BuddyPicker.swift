import SwiftUI

// Pick or add dive buddies for one dive. Known names are one tap away.
struct BuddyPickerSheet: View {
    let diveID: UInt32

    @Environment(\.dismiss) private var dismiss
    @State private var buddyStore = BuddyStore.shared
    @State private var newName = ""

    private var current: [String] { buddyStore.buddies(for: diveID) }

    var body: some View {
        NavigationStack {
            List {
                Section(loc("新潜伴", "NEW BUDDY")) {
                    HStack {
                        TextField(loc("名字…", "Name…"), text: $newName)
                        Button(loc("添加", "Add")) {
                            buddyStore.add(newName, for: diveID)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .font(.system(size: 12, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.abyss)
                    }
                }
                .listRowBackground(Theme.panel)

                Section(loc("一起潜过的人", "PEOPLE YOU'VE DIVED WITH")) {
                    if buddyStore.knownBuddies.isEmpty {
                        Text(loc("还没有记录 — 加第一个吧", "No one yet — add your first"))
                            .font(.system(size: 13)).foregroundStyle(Theme.faint)
                    }
                    ForEach(buddyStore.knownBuddies, id: \.self) { name in
                        Button {
                            buddyStore.toggle(name, for: diveID)
                        } label: {
                            HStack {
                                Image(systemName: current.contains(name)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(current.contains(name)
                                                     ? Theme.accent : Theme.faint)
                                Text(name).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(loc("潜伴", "Buddies"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("完成", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
