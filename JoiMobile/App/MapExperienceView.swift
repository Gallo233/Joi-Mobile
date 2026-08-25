import CompanionCore
import OfflinePack
import SwiftUI

/// The Map surface: one cached cultural walk, how far along it you are, and the
/// way back when you leave it.
///
/// The native map owns presentation only; route progress and journey state stay
/// with their existing owners.
struct MapExperienceView: View {
    let characterName: String
    @Bindable var model: AppModel
    @State private var isRouteLibraryPresented = false

    var body: some View {
        NativeMapSurface(
            characterName: characterName,
            model: model,
            onOpenRouteLibrary: { isRouteLibraryPresented = true }
        )
        .sheet(isPresented: $isRouteLibraryPresented) {
            TravelRouteLibraryView(model: model)
        }
        .sheet(isPresented: Binding(
            get: { model.isRecapPresented },
            set: { if !$0 { model.isRecapPresented = false } }
        )) {
            RouteRecapView(model: model)
        }
    }
}

/// Where the walk has got to in the story: the stop you are at, what it says,
/// and what comes next.
struct RouteStoryStrip: View {
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

/// Where the walker is, and what the route says about it.
///
/// `JM-P0-009`. A confident proposal is stated; an ambiguous one asks, showing
/// every candidate with its distance and identity confidence so the choice is
/// informed rather than a guess between two names. Narration is labelled as
/// cached, because that is the only kind this product has.
struct ArriveAndTellPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let confirmed = model.confirmedPlace {
                HStack(spacing: 6) {
                    Label(confirmed.stop.name, systemImage: "mappin.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.teal)
                    if confirmed.wasCorrected {
                        Text("已更正")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button(String(localized: "不是这里")) { model.clearConfirmedPlace() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                if let narration = model.placeNarration {
                    Text(narration.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(narration.isFactual
                        ? String(localized: "随路线包缓存的资料，未联网核对。")
                        : String(localized: "这是角色的感想，不是有来源的说法。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if model.placeProposal.needsConfirmation {
                Text("你在哪一站？")
                    .font(.subheadline.weight(.semibold))
                Text("定位不够准，无法确定。选一个，或者继续走。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(model.placeProposal.candidates, id: \.stop.stopID) { candidate in
                    Button {
                        model.confirmPlace(candidate.stop)
                    } label: {
                        HStack {
                            Text(candidate.stop.name).font(.footnote)
                            Spacer()
                            Text("约 \(Int(candidate.distanceMeters.rounded())) 米")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
