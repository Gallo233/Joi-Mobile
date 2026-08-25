import CompanionCore
import Foundation
import MapKit
import SwiftUI

/// One Apple Maps search result, reduced to the display facts Map needs.
///
/// The transient result deliberately carries no provider payload, source claim,
/// journey identity or memory eligibility. Selecting it moves the camera; only
/// the separate `SystemMapHandoffModel` confirmation may later pass its name and
/// coordinate back to Apple Maps as an external driving destination.
struct MapSearchResult: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String?
    let coordinate: GeoCoordinate
}

enum MapSearchPhase: Equatable, Sendable {
    case idle
    case loading(query: String)
    case results([MapSearchResult])
    case empty(query: String)
    case offline
    case failed

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
protocol MapSearchProviding {
    func search(query: String, region: MKCoordinateRegion) async throws -> [MapSearchResult]
}

/// The only production adapter for online place search in the current app.
///
/// The request region is the authored route corridor, never the current GPS
/// reading. MapKit remains a search/presentation provider and does not become a
/// Joi source, route planner or journey-state owner.
@MainActor
struct AppleMapSearchProvider: MapSearchProviding {
    func search(query: String, region: MKCoordinateRegion) async throws -> [MapSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.pointOfInterest, .address]

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(MapSearchModel.maximumResults).compactMap { item in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let subtitle = item.placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return MapSearchResult(
                id: "\(name)|\(coordinate.latitude)|\(coordinate.longitude)",
                name: name,
                subtitle: subtitle == name || subtitle?.isEmpty == true ? nil : subtitle,
                coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        }
    }
}

/// Cancellable, transient search state for the Map surface (`G2-J5L`).
///
/// Queries are kept only while the sheet is visible. They are not written to
/// AppModel, the journey store, transcript, memory, defaults, logs or analytics.
@MainActor
@Observable
final class MapSearchModel {
    static let maximumResults = 12

    var query = ""
    private(set) var phase: MapSearchPhase = .idle

    @ObservationIgnored private let provider: any MapSearchProviding
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(provider: any MapSearchProviding = AppleMapSearchProvider()) {
        self.provider = provider
    }

    /// Prefills an inspected Chat handoff without contacting the provider.
    /// Submitting remains the only consent boundary for an Apple Maps request.
    func prepare(query: String) {
        cancelCurrentRequest()
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .idle
    }

    func submit(reachability: NetworkReachability, region: MKCoordinateRegion) {
        let submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        query = submitted
        cancelCurrentRequest()

        guard !submitted.isEmpty else {
            phase = .idle
            return
        }
        guard reachability != .unreachable else {
            phase = .offline
            return
        }

        generation += 1
        let requestGeneration = generation
        phase = .loading(query: submitted)
        task = Task { [weak self, provider] in
            do {
                let found = try await provider.search(query: submitted, region: region)
                try Task.checkCancellation()
                guard let self, self.generation == requestGeneration else { return }
                let bounded = Array(found.prefix(Self.maximumResults))
                self.phase = bounded.isEmpty ? .empty(query: submitted) : .results(bounded)
            } catch is CancellationError {
                // A newer query or a closed sheet owns the visible state now.
            } catch {
                guard let self, self.generation == requestGeneration else { return }
                self.phase = .failed
            }
        }
    }

    func clear() {
        cancelCurrentRequest()
        query = ""
        phase = .idle
    }

    private func cancelCurrentRequest() {
        generation += 1
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

/// Explicit, online-only place search for the Map surface.
///
/// Submitting is the consent moment for an Apple Maps query. The disclosure is
/// kept beside the field, and closing the sheet clears both the text and result
/// list instead of turning search history into hidden app state.
struct MapSearchSheet: View {
    @Bindable var model: MapSearchModel
    let reachability: NetworkReachability
    let region: MKCoordinateRegion
    let onSelect: (MapSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    TextField(String(localized: "搜索地点或地址"), text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .focused($fieldIsFocused)
                        .onSubmit { submit() }

                    Button(String(localized: "搜索"), systemImage: "magnifyingglass") {
                        submit()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(String(localized: "搜索"))
                }

                Label(
                    String(localized: "提交后，搜索文字和当前路线范围会发送给 Apple 地图；不会使用你的实时位置，也不会保存搜索记录。"),
                    systemImage: "hand.raised"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                searchContent
            }
            .padding(16)
            .navigationTitle(String(localized: "搜索地点"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { fieldIsFocused = true }
        .onDisappear { model.clear() }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch model.phase {
        case .idle:
            searchMessage(
                title: String(localized: "搜索路线附近的地点"),
                detail: String(localized: "可以输入博物馆、街道、公园或完整地址。"),
                systemImage: "mappin.and.ellipse"
            )
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "正在搜索 Apple 地图…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .results(results):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.indigo)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let subtitle = result.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        case let .empty(query):
            searchMessage(
                title: String(localized: "没有找到“\(query)”"),
                detail: String(localized: "换一个名称或输入更完整的地址。"),
                systemImage: "magnifyingglass"
            )
        case .offline:
            searchMessage(
                title: String(localized: "当前没有网络"),
                detail: String(localized: "缓存路线仍可使用；地点搜索需要连接 Apple 地图。"),
                systemImage: "wifi.slash"
            )
        case .failed:
            VStack(spacing: 12) {
                searchMessage(
                    title: String(localized: "搜索没有完成"),
                    detail: String(localized: "Apple 地图暂时没有回应，可以重试。"),
                    systemImage: "exclamationmark.triangle"
                )
                Button(String(localized: "重试")) { submit() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func searchMessage(title: String, detail: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        model.submit(reachability: reachability, region: region)
    }
}
