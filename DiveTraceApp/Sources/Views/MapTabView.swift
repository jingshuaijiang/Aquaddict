import SwiftUI
import MapKit
import DiveKit

struct MapTabView: View {
    @Environment(DiveStore.self) private var store
    @State private var siteStore = SiteStore.shared
    @State private var selectedDive: Dive?
    @State private var selectedSite: DiveSite?
    @State private var draftCoordinate: CLLocationCoordinate2D?
    @State private var draftName = ""
    @State private var showDiscover = false

    private var gnssDives: [Dive] {
        store.dives.filter { $0.header.entryLocation != nil }
    }

    private var mappableSites: [DiveSite] {
        siteStore.sites.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var initialPosition: MapCameraPosition {
        var lats = gnssDives.compactMap { $0.header.entryLocation?.latitude }
        var lons = gnssDives.compactMap { $0.header.entryLocation?.longitude }
        lats += mappableSites.compactMap(\.latitude)
        lons += mappableSites.compactMap(\.longitude)
        guard let latMin = lats.min(), let latMax = lats.max(),
              let lonMin = lons.min(), let lonMax = lons.max() else {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 130),
                span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)))
        }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (latMin + latMax) / 2,
                                           longitude: (lonMin + lonMax) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((latMax - latMin) * 1.6, 0.05),
                                   longitudeDelta: max((lonMax - lonMin) * 1.6, 0.05))))
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(initialPosition: initialPosition) {
                    // site pins with dive counts
                    ForEach(mappableSites) { site in
                        Annotation(site.name, coordinate: CLLocationCoordinate2D(
                            latitude: site.latitude!, longitude: site.longitude!)) {
                            Button { selectedSite = site } label: {
                                VStack(spacing: 2) {
                                    ZStack {
                                        Circle().fill(Theme.accent)
                                            .frame(width: 26, height: 26)
                                        Text("\(siteStore.diveCount(at: site.id))")
                                            .font(.system(size: 11, weight: .bold,
                                                          design: .monospaced))
                                            .foregroundStyle(Theme.abyss)
                                    }
                                }
                            }
                        }
                    }
                    // raw GNSS pins for dives not yet assigned to a site
                    ForEach(gnssDives.filter { siteStore.site(for: $0.id) == nil }) { dive in
                        let loc0 = dive.header.entryLocation!
                        Annotation("#\(dive.n)", coordinate: CLLocationCoordinate2D(
                            latitude: loc0.latitude, longitude: loc0.longitude)) {
                            Button { selectedDive = dive } label: {
                                ZStack {
                                    Circle().fill(Theme.accent.opacity(0.25))
                                        .frame(width: 26, height: 26)
                                    Circle().fill(Theme.ink)
                                        .frame(width: 9, height: 9)
                                }
                            }
                        }
                    }
                }
                .mapStyle(.imagery)
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0,
                                                       coordinateSpace: .local))
                        .onEnded { value in
                            if case .second(true, let drag?) = value,
                               let coord = proxy.convert(drag.location, from: .local) {
                                draftName = ""
                                draftCoordinate = coord
                            }
                        })
            }
            .overlay(alignment: .bottom) { hint }
            .navigationTitle(loc("潜水地图", "Dive Map"))
            .toolbarBackground(Theme.abyss, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDiscover = true
                    } label: {
                        Label(loc("发现潜点", "Discover"),
                              systemImage: "sparkle.magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .tint(Theme.accent)
                }
            }
            .sheet(isPresented: $showDiscover) { DiscoverSitesSheet() }
            .sheet(item: $selectedDive) { dive in
                NavigationStack { DiveDetailView(dive: dive) }
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedSite) { site in
                SiteDetailSheet(site: site)
            }
            .alert(loc("新建潜点", "New Dive Site"),
                   isPresented: .init(get: { draftCoordinate != nil },
                                      set: { if !$0 { draftCoordinate = nil } })) {
                TextField(loc("潜点名称", "Site name"), text: $draftName)
                Button(loc("创建", "Create")) {
                    if let c = draftCoordinate,
                       !draftName.trimmingCharacters(in: .whitespaces).isEmpty {
                        siteStore.createSite(
                            name: draftName.trimmingCharacters(in: .whitespaces),
                            latitude: c.latitude, longitude: c.longitude)
                    }
                    draftCoordinate = nil
                }
                Button(loc("取消", "Cancel"), role: .cancel) { draftCoordinate = nil }
            } message: {
                Text(loc("在此位置创建潜点，之后可在日志本批量关联潜水",
                         "Creates a site here — batch-assign dives from the logbook"))
            }
        }
    }

    private var hint: some View {
        Text(mappableSites.isEmpty && gnssDives.isEmpty
             ? loc("长按地图新建潜点 · Perdix 3 的 GNSS 潜水会自动出现",
                   "Long-press to create a site · GNSS dives appear automatically")
             : loc("长按新建潜点 · 圆点为未关联的 GNSS 潜水",
                   "Long-press for new site · dots are unassigned GNSS dives"))
            .font(.system(size: 11)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
    }
}

// Site sheet: rename, see and open its dives, assign more, delete.
struct SiteDetailSheet: View {
    let site: DiveSite

    @Environment(\.dismiss) private var dismiss
    @Environment(DiveStore.self) private var store
    @State private var siteStore = SiteStore.shared
    @State private var name: String = ""
    @State private var showAssign = false

    private var divesHere: [Dive] {
        store.dives.filter { siteStore.site(for: $0.id)?.id == site.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(loc("名称", "NAME")) {
                    TextField(loc("潜点名称", "Site name"), text: $name)
                        .onSubmit { siteStore.renameSite(site.id, to: name) }
                }
                .listRowBackground(Theme.panel)

                Section("\(divesHere.count)" + loc(" 潜", " DIVES")) {
                    ForEach(divesHere.reversed()) { dive in
                        NavigationLink(destination: DiveDetailView(dive: dive)) {
                            HStack {
                                Text("#\(dive.n) · \(dive.dayText)")
                                    .font(.system(size: 13))
                                Spacer()
                                Text(U.depth(dive.maxDepth))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .swipeActions {
                            Button(loc("移除", "Remove"), role: .destructive) {
                                siteStore.unassign(dive.id)
                            }
                        }
                    }
                    Button {
                        showAssign = true
                    } label: {
                        Label(loc("关联更多潜水…", "Assign more dives…"),
                              systemImage: "plus.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .listRowBackground(Theme.panel)

                Section {
                    Button(loc("删除潜点", "Delete site"), role: .destructive) {
                        siteStore.deleteSite(site.id)
                        dismiss()
                    }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("完成", "Done")) {
                        if !name.isEmpty { siteStore.renameSite(site.id, to: name) }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { name = site.name }
        .sheet(isPresented: $showAssign) {
            DiveMultiPickerSheet(siteID: site.id)
        }
    }
}

// Pick multiple dives to attach to an existing site.
struct DiveMultiPickerSheet: View {
    let siteID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(DiveStore.self) private var store
    @State private var siteStore = SiteStore.shared
    @State private var selected: Set<UInt32> = []

    var body: some View {
        NavigationStack {
            List(store.dives.reversed()) { dive in
                Button {
                    if selected.contains(dive.id) { selected.remove(dive.id) }
                    else { selected.insert(dive.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(dive.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(dive.id)
                                             ? Theme.accent : Theme.faint)
                        Text("#\(dive.n) · \(dive.dayText)")
                            .font(.system(size: 13)).foregroundStyle(Theme.ink)
                        Spacer()
                        if let s = siteStore.site(for: dive.id) {
                            Text(s.name).font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.abyss)
            .navigationTitle(loc("选择潜水", "Select Dives"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("关联 \(selected.count)", "Assign \(selected.count)")) {
                        siteStore.assign(Array(selected), to: siteID)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

extension Dive: Equatable {
    static func == (lhs: Dive, rhs: Dive) -> Bool { lhs.id == rhs.id }
}
