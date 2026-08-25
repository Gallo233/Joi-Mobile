import MapKit
import OfflinePack
import SwiftUI

private enum MapCameraMode {
    case route
    case user
    case free
}

/// The interactive MapKit presentation of a cached cultural walk.
///
/// MapKit supplies the online basemap and selectable points of interest. Joi's
/// cached route, stops, narration and progress are drawn over it and remain
/// usable without promising that Apple's tiles are downloadable offline.
struct NativeMapSurface: View {
    let characterName: String
    @Bindable var model: AppModel
    let onImportPack: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraMode: MapCameraMode = .route
    @State private var selectedMapFeature: MapFeature?
    @State private var selectedSearchResult: MapSearchResult?
    @State private var isSearchPresented = false
    @State private var searchModel = MapSearchModel()
    @State private var systemMapHandoff = SystemMapHandoffModel()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                routeMap
                contextDrawer
                    .frame(height: drawerHeight(for: proxy.size.height))
            }
            // `RootShellView` owns the persistent Chat/Map switcher. Keeping its
            // clearance outside the drawer makes every map action reachable.
            .padding(.bottom, 82)
            .background(Color(.secondarySystemBackground))
        }
        .onAppear {
            showRoute(animated: false)
            receivePendingSearch()
        }
        .onChange(of: model.walk.route.routeID) {
            selectedMapFeature = nil
            selectedSearchResult = nil
            searchModel.clear()
            systemMapHandoff.reset()
            showRoute()
        }
        .onChange(of: model.walkLocation.latest) { _, observation in
            guard cameraMode == .user, let observation else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(MapRoutePresentation.userRegion(around: observation.coordinate))
            }
        }
    }

    private var routeMap: some View {
        let routeCoordinates = model.walk.route.coordinates.map(MapRoutePresentation.coordinate)
        let completed = MapRoutePresentation.completedCoordinates(
            from: model.walk.route.coordinates,
            progress: model.isWalking ? model.walkProgress : 0
        )

        return Map(
            position: $cameraPosition,
            interactionModes: .all,
            selection: $selectedMapFeature
        ) {
            // A white casing keeps the cached route legible over roads, water
            // and satellite-derived land colors without hiding map labels.
            MapPolyline(coordinates: routeCoordinates)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: routeCoordinates)
                .stroke(.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

            if completed.count > 1 {
                MapPolyline(coordinates: completed)
                    .stroke(.indigo, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }

            ForEach(Array(model.narrativeState.stops.enumerated()), id: \.element.stop.stopID) { index, entry in
                Annotation(
                    entry.stop.name,
                    coordinate: MapRoutePresentation.coordinate(entry.stop.coordinate),
                    anchor: .bottom
                ) {
                    RouteStopMarker(
                        number: index + 1,
                        completed: entry.completion == .completed
                    )
                }
            }

            // Do not display the last precise fix once the user visibly ends a
            // walk. The provider may retain it in memory, but Map stops showing
            // and following it at the same boundary as collection.
            if model.isWalking, let location = model.walkLocation.latest?.coordinate {
                Annotation(
                    String(localized: "我的位置"),
                    coordinate: MapRoutePresentation.coordinate(location)
                ) {
                    WalkerMarker(
                        offRoute: model.walkObservation?.navigationObservation.offRoute ?? false
                    )
                }
            }

            if let result = selectedSearchResult {
                Annotation(
                    result.name,
                    coordinate: MapRoutePresentation.coordinate(result.coordinate),
                    anchor: .bottom
                ) {
                    SearchResultMarker()
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .all))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .mapFeatureSelectionAccessory(.automatic)
        .onMapCameraChange(frequency: .onEnd) {
            if cameraPosition.positionedByUser { cameraMode = .free }
        }
        .overlay(alignment: .top) { mapHeader }
        .overlay(alignment: .bottomTrailing) { cameraControls }
        .sheet(isPresented: $isSearchPresented) {
            MapSearchSheet(
                model: searchModel,
                reachability: model.networkMonitor.reachability,
                region: MKCoordinateRegion(MapRoutePresentation.routeRect(for: model.walk.route.coordinates)),
                onSelect: selectSearchResult
            )
        }
        .confirmationDialog(
            String(localized: "交给 Apple 地图驾车？"),
            isPresented: systemMapConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "打开 Apple 地图")) {
                systemMapHandoff.confirm()
            }
            Button(String(localized: "取消"), role: .cancel) {
                systemMapHandoff.cancel()
            }
        } message: {
            if case let .confirming(destination) = systemMapHandoff.phase {
                Text(
                    String(
                        localized: "将把“\(destination.name)”的名称和坐标交给 Apple 地图。路线和后续位置由系统地图处理，Joi 不会开始或保存这段导航。"
                    )
                )
            }
        }
    }

    /// Opens the existing disclosed search flow with a one-time Chat query.
    /// `prepare` is intentionally not `submit`: changing surfaces cannot send a
    /// conversation-derived string to Apple Maps by itself.
    private func receivePendingSearch() {
        guard let query = model.consumePendingMapSearchQuery() else { return }
        searchModel.prepare(query: query)
        isSearchPresented = true
    }

    private var mapHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.walk.title, systemImage: "figure.walk")
                        .font(.headline)
                        .lineLimit(2)
                    Label(
                        model.installedPack == nil
                            ? String(localized: "示例路线 · 资料已缓存")
                            : String(localized: "已校验路线包 · 资料已缓存"),
                        systemImage: "arrow.down.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
                }
                Spacer(minLength: 0)
                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
                .accessibilityLabel(String(localized: "搜索地点"))
                .accessibilityHint(String(localized: "在线搜索地点或地址"))
            }

            if let result = selectedSearchResult {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let subtitle = result.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        showRoute()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "清除搜索结果"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var cameraControls: some View {
        HStack(spacing: 6) {
            Button {
                showRoute()
            } label: {
                Label(String(localized: "路线总览"), systemImage: "map")
                    .frame(minHeight: 36)
            }
            .accessibilityHint(String(localized: "让整条路线重新出现在地图中"))

            if model.isWalking, let location = model.walkLocation.latest?.coordinate {
                Button {
                    cameraMode = .user
                    withAnimation(.easeInOut(duration: 0.35)) {
                        cameraPosition = .region(MapRoutePresentation.userRegion(around: location))
                    }
                } label: {
                    Label(String(localized: "我的位置"), systemImage: "location.fill")
                        .frame(minHeight: 36)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.indigo)
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
    }

    private var contextDrawer: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.isWalking {
                        ProgressView(value: model.walkProgress)
                            .tint(.indigo)
                        Text(progressLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let guidance = model.walkGuidance {
                            Label(guidance, systemImage: model.walkObservation?.arrived == true
                                ? "flag.checkered"
                                : "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(model.walkObservation?.arrived == true ? .teal : .orange)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    (model.walkObservation?.arrived == true ? Color.teal : Color.orange).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }

                        RouteStoryStrip(state: model.narrativeState)
                        ArriveAndTellPanel(model: model)
                        if selectedSearchResult != nil {
                            Label(
                                String(localized: "先结束当前步行，才能把所选地点交给系统地图。"),
                                systemImage: "car.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else if let result = selectedSearchResult {
                        Label(String(localized: "已选择目的地"), systemImage: "mappin.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 7) {
                            Label(
                                String(localized: "这是 Apple 地图搜索结果，不是当前文化路线的一站。"),
                                systemImage: "info.circle"
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                            if systemMapOpenFailed(for: result) {
                                Label(
                                    String(localized: "没有打开系统地图；目的地仍保留，可以重试。"),
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(String(localized: "确认后由 Apple 地图规划驾车路线；Joi 不会开始或保存这段导航。"))
                                    .font(.caption)
                                    .foregroundStyle(Color.primary.opacity(0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.indigo.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .accessibilityElement(children: .combine)
                    } else {
                        Label(
                            String(localized: "与 \(characterName) 一起走"),
                            systemImage: "sparkles"
                        )
                        .font(.subheadline.weight(.semibold))
                        Text(routeSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Label(
                            String(localized: "路线、站点和讲解已缓存；Apple 底图需要网络。"),
                            systemImage: "network"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let message = model.packImportMessage {
                        HStack(alignment: .firstTextBaseline) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button {
                                model.acknowledgePackMessage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "关闭提示"))
                        }
                    }

                    if let availability = availabilityMessage {
                        Label(availability, systemImage: "location.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .clipped()

            Divider()
            secondaryActions
                .padding(.horizontal, 14)
                .padding(.top, 10)

            primaryAction
        }
        .background(.regularMaterial)
        .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        HStack(spacing: 10) {
            if selectedSearchResult != nil, !model.isWalking {
                drawerButton(String(localized: "返回文化路线"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    showRoute()
                }
            } else if !model.walkRecap.isEmpty {
                drawerButton(String(localized: "行程回顾"), systemImage: "list.bullet.rectangle") {
                    model.isRecapPresented = true
                }
            }
            if model.canOfferJourneyAttachment, selectedSearchResult == nil {
                drawerButton(String(localized: "在对话里问"), systemImage: "bubble.left.and.text.bubble.right") {
                    Task { await model.offerJourneyAttachment() }
                }
            }
            if !model.isWalking {
                drawerButton(String(localized: "导入路线包"), systemImage: "square.and.arrow.down") {
                    onImportPack()
                }
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let result = selectedSearchResult, !model.isWalking {
            Button {
                systemMapHandoff.proposeDriving(to: result)
            } label: {
                Label(String(localized: "用 Apple 地图驾车"), systemImage: "car.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else {
            Button {
                if model.isWalking {
                    model.stopWalk()
                    if selectedSearchResult == nil { showRoute() }
                } else {
                    cameraMode = .user
                    model.startWalk()
                }
            } label: {
                Label(
                    model.isWalking ? String(localized: "结束步行") : String(localized: "开始步行"),
                    systemImage: model.isWalking ? "stop.fill" : "figure.walk"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isWalking ? .orange : .teal)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func drawerButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
    }

    private var routeSummary: String {
        let stops = model.walk.narrative.stops.count
        let totalSeconds = model.walk.narrative.stops.reduce(0) {
            $0 + $1.stop.suggestedDurationSeconds
        }
        let minutes = max(1, Int(ceil(Double(totalSeconds) / 60)))
        return String(localized: "\(stops) 个文化站点 · 建议 \(minutes) 分钟")
    }

    private var progressLabel: String {
        String(localized: "已完成 \(Int((model.walkProgress * 100).rounded()))%")
    }

    /// Only shown when location cannot follow, so a walk that is working says
    /// nothing at all.
    private var availabilityMessage: String? {
        switch model.walkLocation.availability {
        case .idle, .following: nil
        case .waitingForPermission: String(localized: "正在请求位置权限……")
        case .denied: String(localized: "没有位置权限，无法沿路线前进；可在系统设置里开启。")
        case .unavailable: String(localized: "这台设备的定位服务不可用。")
        }
    }

    private func drawerHeight(for totalHeight: CGFloat) -> CGFloat {
        if model.isWalking {
            return min(max(totalHeight * 0.46, 330), 380)
        }
        if selectedSearchResult != nil {
            return min(max(totalHeight * 0.42, 330), 360)
        }
        return 252
    }

    private func showRoute(animated: Bool = true) {
        cameraMode = .route
        selectedSearchResult = nil
        systemMapHandoff.reset()
        let position = MapCameraPosition.rect(
            MapRoutePresentation.routeRect(for: model.walk.route.coordinates)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { cameraPosition = position }
        } else {
            cameraPosition = position
        }
    }

    private func selectSearchResult(_ result: MapSearchResult) {
        selectedMapFeature = nil
        selectedSearchResult = result
        systemMapHandoff.reset()
        cameraMode = .free
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MapRoutePresentation.searchResultRegion(around: result.coordinate))
        }
    }

    private var systemMapConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirming = systemMapHandoff.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { systemMapHandoff.cancel() }
            }
        )
    }

    private func systemMapOpenFailed(for result: MapSearchResult) -> Bool {
        guard case let .failed(failed) = systemMapHandoff.phase else { return false }
        return failed.id == result.id
    }
}

private struct RouteStopMarker: View {
    let number: Int
    let completed: Bool

    var body: some View {
        ZStack {
            Circle().fill(completed ? Color.teal : Color.white)
            Circle().stroke(Color.teal, lineWidth: 3)
            if completed {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            } else {
                Text(verbatim: "\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
            }
        }
        .frame(width: 30, height: 30)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

private struct WalkerMarker: View {
    let offRoute: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill((offRoute ? Color.orange : Color.indigo).opacity(0.18))
                .frame(width: 38, height: 38)
            Circle()
                .fill(offRoute ? Color.orange : Color.indigo)
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "figure.walk")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
                .overlay { Circle().stroke(.white, lineWidth: 3) }
        }
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
}

private struct SearchResultMarker: View {
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title)
            .foregroundStyle(.indigo)
            .padding(4)
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
}
