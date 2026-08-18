import CompanionCore
import SwiftUI

/// The Map surface: one cached cultural walk, how far along it you are, and the
/// way back when you leave it.
///
/// There is no basemap, deliberately. DEC-004 promises the corridor of a
/// downloaded route, progress along it, and return guidance — not a tile-rendered
/// map, which needs a renderer and tile rights this build does not have. Drawing
/// the route's own shape keeps the promise exactly and claims nothing else.
struct MapExperienceView: View {
    let characterName: String
    let model: AppModel

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

                if let guidance = model.walkGuidance {
                    Label(guidance, systemImage: model.walkObservation?.arrived == true
                        ? "flag.checkered"
                        : "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(model.walkObservation?.arrived == true ? .teal : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    if model.canOfferJourneyAttachment {
                        // Hands this walk to the conversation for one turn. It
                        // opens a preview in Chat; nothing is sent from here.
                        Button(String(localized: "在对话里问"), systemImage: "bubble.left.and.text.bubble.right") {
                            Task { await model.offerJourneyAttachment() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
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
    }

    private var header: some View {
        HStack {
            Label(model.walk.title, systemImage: "figure.walk")
                .font(.headline)
            Spacer()
            Label(String(localized: "离线可用"), systemImage: "arrow.down.circle.fill")
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
