import OfflinePack
import SwiftUI

/// Transient presentation state for inspecting authored route stops.
///
/// This deliberately stores only identities. `RouteNarrative` remains the
/// authority for ordered content, and browsing has no path to journey progress,
/// place confirmation, memory or persistence.
struct RouteStopBrowser: Equatable {
    private(set) var routeID: String?
    private(set) var selectedStopID: String?

    mutating func synchronize(routeID: String, stopIDs: [String]) {
        if self.routeID != routeID {
            self.routeID = routeID
            selectedStopID = nil
            return
        }
        if let selectedStopID, !stopIDs.contains(selectedStopID) {
            self.selectedStopID = nil
        }
    }

    @discardableResult
    mutating func select(stopID: String, routeID: String, stopIDs: [String]) -> Bool {
        synchronize(routeID: routeID, stopIDs: stopIDs)
        guard stopIDs.contains(stopID) else {
            selectedStopID = nil
            return false
        }
        selectedStopID = stopID
        return true
    }

    mutating func clear() {
        selectedStopID = nil
    }

    func selectedIndex(in stopIDs: [String]) -> Int? {
        guard let selectedStopID else { return nil }
        return stopIDs.firstIndex(of: selectedStopID)
    }

    @discardableResult
    mutating func move(
        by offset: Int,
        routeID: String,
        stopIDs: [String]
    ) -> String? {
        synchronize(routeID: routeID, stopIDs: stopIDs)
        guard
            let index = selectedIndex(in: stopIDs),
            stopIDs.indices.contains(index + offset)
        else { return selectedStopID }

        selectedStopID = stopIDs[index + offset]
        return selectedStopID
    }
}

/// The whole authored route, available before location or a walk begins.
struct RouteItineraryView: View {
    let routeTitle: String
    let stops: [StopProgress]
    let selectedStopID: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(stops.enumerated()), id: \.element.stop.stopID) { index, entry in
                        Button {
                            onSelect(entry.stop.stopID)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                stopNumber(index + 1, selected: entry.stop.stopID == selectedStopID)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.stop.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(durationLabel(for: entry.stop))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    sourceLabel(for: entry.stop)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(localized: "第 \(index + 1) 站：\(entry.stop.name)")
                        )
                        .accessibilityHint(String(localized: "查看缓存讲解和资料版本"))
                    }
                } header: {
                    Text(routeTitle)
                } footer: {
                    Text(String(localized: "打开站点只浏览缓存内容，不会标记到达或推进路线。"))
                }
            }
            .navigationTitle(String(localized: "路线站点"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
    }

    private func stopNumber(_ number: Int, selected: Bool) -> some View {
        Text(verbatim: "\(number)")
            .font(.caption.bold())
            .foregroundStyle(selected ? Color.white : Color.teal)
            .frame(width: 28, height: 28)
            .background(selected ? Color.indigo : Color.teal.opacity(0.12), in: Circle())
            .overlay { Circle().stroke(selected ? Color.indigo : Color.teal, lineWidth: 1.5) }
    }

    private func durationLabel(for stop: RouteStop) -> String {
        let minutes = max(1, Int(ceil(stop.suggestedDurationSeconds / 60)))
        return String(localized: "建议停留 \(minutes) 分钟")
    }

    @ViewBuilder
    private func sourceLabel(for stop: RouteStop) -> some View {
        if stop.isFactual {
            Label(
                String(localized: "缓存资料 · \(stop.sourceRevisionIDs.count) 个版本"),
                systemImage: "doc.text.magnifyingglass"
            )
            .foregroundStyle(.teal)
        } else {
            Label(String(localized: "角色感想 · 无资料引用"), systemImage: "quote.bubble")
                .foregroundStyle(.secondary)
        }
    }
}

struct RouteStopInspectionCard: View {
    let entry: StopProgress
    let number: Int
    let total: Int
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "第 \(number) 站，共 \(total) 站"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.58))
                .accessibilityLabel(String(localized: "关闭站点详情"))
            }

            Text(entry.stop.name)
                .font(.headline)
            Text(entry.stop.narration)
                .font(.footnote)
                .foregroundStyle(Color.primary.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            if entry.stop.isFactual {
                Label(
                    String(localized: "随路线包缓存的资料，未联网核对。"),
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(.caption)
                .foregroundStyle(.teal)
                ForEach(entry.stop.sourceRevisionIDs, id: \.self) { revision in
                    Text(revision)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.primary.opacity(0.68))
                        .textSelection(.enabled)
                }
            } else {
                Label(
                    String(localized: "这是角色的感想，不是有来源的说法。"),
                    systemImage: "quote.bubble"
                )
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.72))
            }

            HStack(spacing: 10) {
                Button(action: onSelectPrevious) {
                    Label(String(localized: "上一站"), systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .disabled(!canSelectPrevious)
                Button(action: onSelectNext) {
                    Label(String(localized: "下一站"), systemImage: "chevron.right")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .disabled(!canSelectNext)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.indigo)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}
