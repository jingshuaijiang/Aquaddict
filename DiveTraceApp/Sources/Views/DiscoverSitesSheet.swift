import SwiftUI
import MapKit
import DiveKit

// Review sheet for auto-discovered dive sites: one section per dive cluster,
// tap a candidate to create the site there and assign the whole cluster.
struct DiscoverSitesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiveStore.self) private var store
    @State private var siteStore = SiteStore.shared
    @State private var clusters: [DiveCluster]? = nil
    @State private var handled: Set<UUID> = []

    private var unassignedGNSS: [Dive] {
        store.dives.filter {
            $0.header.entryLocation != nil && siteStore.site(for: $0.id) == nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let clusters {
                    if clusters.isEmpty {
                        ContentUnavailableView(
                            loc("没有待关联的 GNSS 潜水", "No unassigned GNSS dives"),
                            systemImage: "checkmark.circle")
                    } else {
                        list(clusters)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.accent)
                        Text(loc("正在搜索附近的著名潜点…", "Searching nearby dive sites…"))
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.abyss)
            .navigationTitle(loc("发现潜点", "Discover Sites"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("完成", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            clusters = await NearbySites.discover(dives: unassignedGNSS)
        }
    }

    private func list(_ clusters: [DiveCluster]) -> some View {
        List {
            ForEach(clusters) { cluster in
                Section {
                    if handled.contains(cluster.id) {
                        Label(loc("已关联", "Assigned"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.good).font(.system(size: 13))
                    } else if cluster.candidates.isEmpty {
                        Text(loc("附近没搜到已知潜点 — 可在地图长按手动新建",
                                 "No known sites found — long-press the map to create one"))
                            .font(.system(size: 12)).foregroundStyle(Theme.faint)
                    } else {
                        ForEach(cluster.candidates) { candidate in
                            Button {
                                adopt(candidate, for: cluster)
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
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
                } header: {
                    Text(loc("潜水 ", "DIVES ")
                         + cluster.diveNumbers.map { "#\($0)" }.joined(separator: " "))
                }
                .listRowBackground(Theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func adopt(_ candidate: SiteCandidate, for cluster: DiveCluster) {
        // reuse an existing same-named site if the user already has one
        let site = siteStore.sites.first { $0.name == candidate.name }
            ?? siteStore.createSite(name: candidate.name,
                                    latitude: candidate.coordinate.latitude,
                                    longitude: candidate.coordinate.longitude)
        siteStore.assign(cluster.diveIDs, to: site.id)
        handled.insert(cluster.id)
    }
}
