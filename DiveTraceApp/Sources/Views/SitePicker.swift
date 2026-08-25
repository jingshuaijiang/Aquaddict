import SwiftUI
import MapKit
import DiveKit

// Assign one or many dives to a site: pick from the library or create inline.
// A site created here inherits the first dive's GNSS position when available;
// sites can also be created by long-pressing the map.
struct SitePickerSheet: View {
    let dives: [Dive]
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var siteStore = SiteStore.shared
    @State private var newName = ""
    @State private var nearby: [SiteCandidate]? = nil
    @State private var searching = false

    private var searchCenter: GeoPoint? {
        dives.compactMap { $0.anyLocation }.first
    }

    var body: some View {
        NavigationStack {
            List {
                if searchCenter != nil {
                    Section(loc("附近潜点", "NEARBY SITES")) {
                        if searching {
                            HStack(spacing: 8) {
                                ProgressView().tint(Theme.accent)
                                Text(loc("搜索 Apple 地图 + OpenStreetMap…",
                                         "Searching Apple Maps + OpenStreetMap…"))
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        } else if let nearby, nearby.isEmpty {
                            Text(loc("5 公里内没搜到已知潜点", "No known sites within 5 km"))
                                .font(.system(size: 12)).foregroundStyle(Theme.faint)
                        } else if let nearby {
                            ForEach(nearby) { candidate in
                                Button {
                                    adopt(candidate)
                                } label: {
                                    HStack {
                                        Image(systemName: "sparkle")
                                            .foregroundStyle(Theme.accent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                            Text(String(format: loc("距离 %.0f m", "%.0f m away"),
                                                        candidate.distanceM)
                                                 + " · \(candidate.source)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                        Text(loc("建立并关联", "Adopt"))
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.panel)
                }

                Section {
                    HStack {
                        TextField(loc("新潜点名称…", "New site name…"), text: $newName)
                            .textFieldStyle(.plain)
                        Button(loc("创建并关联", "Create")) {
                            create()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .font(.system(size: 12, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.abyss)
                    }
                } header: {
                    Text(loc("新建", "CREATE"))
                } footer: {
                    if dives.first?.anyLocation != nil {
                        Text(loc("将使用所选潜水的 GNSS 坐标",
                                 "Uses the selected dive's GNSS position"))
                    } else {
                        Text(loc("无坐标 — 也可以在地图上长按新建潜点",
                                 "No coordinates — you can also long-press the map to create a site"))
                    }
                }
                .listRowBackground(Theme.panel)

                Section(loc("潜点库", "SITE LIBRARY")) {
                    if siteStore.sites.isEmpty {
                        Text(loc("还没有潜点", "No sites yet"))
                            .foregroundStyle(Theme.faint).font(.system(size: 13))
                    }
                    ForEach(siteStore.sites) { site in
                        Button {
                            siteStore.assign(dives.map(\.id), to: site.id)
                            finish()
                        } label: {
                            HStack {
                                Image(systemName: site.latitude != nil
                                      ? "mappin.circle.fill" : "mappin.slash.circle")
                                    .foregroundStyle(Theme.accent)
                                Text(site.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(siteStore.diveCount(at: site.id))" + loc(" 潜", ""))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .onDelete { idx in
                        idx.map { siteStore.sites[$0].id }.forEach(siteStore.deleteSite)
                    }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(dives.count == 1
                ? loc("关联潜点", "Assign Site")
                : loc("关联 \(dives.count) 潜到潜点", "Assign \(dives.count) Dives"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消", "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard let center = searchCenter, nearby == nil else { return }
            searching = true
            nearby = await NearbySites.searchCandidates(
                near: CLLocationCoordinate2D(latitude: center.latitude,
                                             longitude: center.longitude))
            searching = false
        }
    }

    private func adopt(_ candidate: SiteCandidate) {
        let site = siteStore.sites.first { $0.name == candidate.name }
            ?? siteStore.createSite(name: candidate.name,
                                    latitude: candidate.coordinate.latitude,
                                    longitude: candidate.coordinate.longitude)
        siteStore.assign(dives.map(\.id), to: site.id)
        finish()
    }

    private func create() {
        let loc0 = dives.first?.anyLocation
        let site = siteStore.createSite(name: newName.trimmingCharacters(in: .whitespaces),
                                        latitude: loc0?.latitude,
                                        longitude: loc0?.longitude)
        siteStore.assign(dives.map(\.id), to: site.id)
        finish()
    }

    private func finish() {
        dismiss()
        onDone?()
    }
}
