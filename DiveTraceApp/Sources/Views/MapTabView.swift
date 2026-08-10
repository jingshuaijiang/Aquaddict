import SwiftUI
import MapKit

struct MapTabView: View {
    var body: some View {
        NavigationStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 130),
                span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120))))
                .mapStyle(.imagery)
                .overlay(alignment: .bottom) {
                    Text("你的潜水暂无坐标 — 建潜点后批量关联，或在详情页逐潜标记")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
                .navigationTitle("潜水地图")
                .toolbarBackground(Theme.abyss, for: .navigationBar)
        }
    }
}
