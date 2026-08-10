import SwiftUI
import MapKit
import DiveKit

struct MapTabView: View {
    @Environment(DiveStore.self) private var store
    @State private var selected: Dive?

    private var located: [Dive] {
        store.dives.filter { $0.header.entryLocation != nil }
    }

    private var initialPosition: MapCameraPosition {
        guard !located.isEmpty else {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 130),
                span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)))
        }
        let lats = located.compactMap { $0.header.entryLocation?.latitude }
        let lons = located.compactMap { $0.header.entryLocation?.longitude }
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.05),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.05))
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        NavigationStack {
            Map(initialPosition: initialPosition) {
                ForEach(located) { dive in
                    let loc = dive.header.entryLocation!
                    Annotation("#\(dive.n)", coordinate: CLLocationCoordinate2D(
                        latitude: loc.latitude, longitude: loc.longitude)) {
                        Button { selected = dive } label: {
                            ZStack {
                                Circle().fill(Theme.accent.opacity(0.25))
                                    .frame(width: 30, height: 30)
                                Circle().fill(Theme.accent)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                }
            }
            .mapStyle(.imagery)
            .overlay(alignment: .bottom) {
                if located.isEmpty {
                    Text("暂无带坐标的潜水 — Perdix 3 的 GNSS 潜水下载后会自动出现在这里")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                } else {
                    Text("\(located.count) 潜有 GNSS 坐标")
                        .font(.system(size: 11)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("潜水地图")
            .toolbarBackground(Theme.abyss, for: .navigationBar)
            .sheet(item: $selected) { dive in
                NavigationStack { DiveDetailView(dive: dive) }
                    .presentationDetents([.large])
            }
        }
    }
}

extension Dive: Equatable {
    static func == (lhs: Dive, rhs: Dive) -> Bool { lhs.id == rhs.id }
}
