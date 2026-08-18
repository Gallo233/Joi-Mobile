import CompanionCore
import OfflinePack
import SwiftUI
import UniformTypeIdentifiers

/// The Map surface: one cached cultural walk, how far along it you are, and the
/// way back when you leave it.
///
/// There is no basemap, deliberately. DEC-004 promises the corridor of a
/// downloaded route, progress along it, and return guidance — not a tile-rendered
/// map, which needs a renderer and tile rights this build does not have. Drawing
/// the route's own shape keeps the promise exactly and claims nothing else.
struct MapExperienceView: View {
    let characterName: String
    @Bindable var model: AppModel
    @State private var isImportingPack = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.teal.opacity(0.25), Color.blue.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                RouteCorridor(
                    walk: model.walk,
                    progress: model.walkProgress,
                    here: model.walkLocation.latest?.coordinate,
                    offRoute: model.walkObservation?.navigationObservation.offRoute ?? false
                )
                .frame(height: 190)
                .accessibilityLabel(String(localized: "路线示意图"))
                .accessibilityValue(progressLabel)

                if model.isWalking {
                    ProgressView(value: model.walkProgress)
                        .tint(.teal)
                    Text(progressLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // The story, not just the line: where you are, what it says,
                // and what is next (`G2-J4B`).
                if model.isWalking {
                    RouteStoryStrip(state: model.narrativeState)
                }

                if let guidance = model.walkGuidance {
                    Label(guidance, systemImage: model.walkObservation?.arrived == true
                        ? "flag.checkered"
                        : "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(model.walkObservation?.arrived == true ? .teal : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message = model.packImportMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { model.acknowledgePackMessage() }
                }

                if let availability = availabilityMessage {
                    Text(availability)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                HStack {
                    Label(characterName, systemImage: "sparkles")
                    Spacer()
                    if !model.walkRecap.isEmpty {
                        Button(String(localized: "行程回顾"), systemImage: "list.bullet.rectangle") {
                            model.isRecapPresented = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                    }
                    if model.canOfferJourneyAttachment {
                        // Hands this walk to the conversation for one turn. It
                        // opens a preview in Chat; nothing is sent from here.
                        Button(String(localized: "在对话里问"), systemImage: "bubble.left.and.text.bubble.right") {
                            Task { await model.offerJourneyAttachment() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
                    }
                    if !model.isWalking {
                        Button(String(localized: "导入路线包"), systemImage: "square.and.arrow.down") {
                            isImportingPack = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                    Button(model.isWalking ? String(localized: "结束步行") : String(localized: "开始步行")) {
                        if model.isWalking { model.stopWalk() } else { model.startWalk() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isWalking ? .secondary : .teal)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 82)
            .accessibilityElement(children: .contain)
        }
        .fileImporter(
            isPresented: $isImportingPack,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await model.importTravelPack(at: url) }
        }
        .sheet(isPresented: Binding(
            get: { model.isRecapPresented },
            set: { if !$0 { model.isRecapPresented = false } }
        )) {
            RouteRecapView(model: model)
        }
    }

    private var header: some View {
        HStack {
            Label(model.walk.title, systemImage: "figure.walk")
                .font(.headline)
            Spacer()
            // A verified pack says so; the bundled walk says it is a sample.
            // `離線可用` on its own would let the two read alike.
            Label(
                model.installedPack == nil
                    ? String(localized: "示例 · 离线可用")
                    : String(localized: "已校验路线包 · 离线可用"),
                systemImage: "arrow.down.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.teal)
        }
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
}

/// The cached route drawn as its own shape: the corridor, the walked part, and
/// where you are.
private struct RouteCorridor: View {
    let walk: CachedWalk
    let progress: Double
    let here: GeoCoordinate?
    let offRoute: Bool

    var body: some View {
        GeometryReader { proxy in
            let aspect = proxy.size.width / max(proxy.size.height, 1)
            let points = walk.normalizedPath(aspect: Double(aspect))
            Canvas { context, size in
                guard points.count > 1 else { return }
                func place(_ point: (x: Double, y: Double)) -> CGPoint {
                    CGPoint(x: point.x * size.width, y: point.y * size.height)
                }

                var corridor = Path()
                corridor.move(to: place(points[0]))
                for point in points.dropFirst() { corridor.addLine(to: place(point)) }

                // The whole route, then the part already walked drawn over it, so
                // progress reads as a filled length rather than a number.
                context.stroke(
                    corridor,
                    with: .color(.teal.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                )
                if progress > 0 {
                    let walked = corridor.trimmedPath(from: 0, to: min(max(progress, 0), 1))
                    context.stroke(
                        walked,
                        with: .color(.teal),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                    )
                }

                for point in [points.first, points.last].compactMap({ $0 }) {
                    let dot = CGRect(x: place(point).x - 5, y: place(point).y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: dot), with: .color(.teal))
                }

                if let here, let me = walk.normalizedPoint(here, aspect: Double(aspect)) {
                    let ring = CGRect(x: place(me).x - 9, y: place(me).y - 9, width: 18, height: 18)
                    context.fill(
                        Path(ellipseIn: ring),
                        with: .color(offRoute ? .orange : .indigo)
                    )
                    context.stroke(
                        Path(ellipseIn: ring.insetBy(dx: -3, dy: -3)),
                        with: .color(.white.opacity(0.85)),
                        lineWidth: 2
                    )
                }
            }
        }
    }
}

/// Where the walk has got to in the story: the stop you are at, what it says,
/// and what comes next.
private struct RouteStoryStrip: View {
    let state: RouteNarrativeState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(state.stops, id: \.stop.stopID) { entry in
                    Circle()
                        .fill(entry.completion == .completed ? Color.teal : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                Text("已到 \(state.completedCount)/\(state.stops.count) 站")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let current = state.currentStop {
                Text(current.name)
                    .font(.subheadline.weight(.semibold))
                Text(current.narration)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !current.isFactual {
                    // Said out loud, because the recap makes the same
                    // distinction and the walk should not blur it first.
                    Text("这是角色的感想，不是有来源的说法。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let next = state.nextStop {
                Label(String(localized: "下一站：\(next.name)"), systemImage: "arrow.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.teal)
            } else {
                Label(String(localized: "所有站点都走完了"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The trip recap, built locally from the stops actually reached.
///
/// Facts and the character's reflections are shown in separate sections, and
/// only a fact may be kept: `JM-P0-012` asks for a recap that distinguishes the
/// two, and putting the model's passing remark into durable memory wearing the
/// clothes of something learned is exactly what that distinction prevents.
struct RouteRecapView: View {
    @Bindable var model: AppModel

    private var facts: [RecapEntry] { model.walkRecap.filter(\.isFact) }
    private var reflections: [RecapEntry] { model.walkRecap.filter { !$0.isFact } }

    var body: some View {
        NavigationStack {
            List {
                if !facts.isEmpty {
                    Section {
                        ForEach(facts, id: \.stopID) { entry in
                            if case let .fact(_, name, text, revisions) = entry {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name).font(.caption.weight(.semibold))
                                    Text(text).font(.callout)
                                    ForEach(revisions, id: \.self) { revision in
                                        Text(revision)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Button(String(localized: "记住这条")) {
                                        Task { await model.proposeMemory(from: entry) }
                                    }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.indigo)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("有来源的部分")
                    } footer: {
                        Text("每条都附有资料版本，可以单独保存到记忆。")
                    }
                }

                if !reflections.isEmpty {
                    Section {
                        ForEach(reflections, id: \.stopID) { entry in
                            if case let .reflection(_, name, text) = entry {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name).font(.caption.weight(.semibold))
                                    Text(text).font(.callout).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("角色的感想")
                    } footer: {
                        Text("这些是角色自己的话，没有资料支持，也不会保存为记忆。")
                    }
                }
            }
            .navigationTitle(String(localized: "行程回顾"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { model.isRecapPresented = false }
                }
            }
        }
    }
}
