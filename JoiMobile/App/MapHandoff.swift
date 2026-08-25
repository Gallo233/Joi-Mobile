import SwiftUI

/// One inspected Chat → Map proposal (`G2-J5M`).
///
/// This is deliberately an App-only presentation contract. It carries the one
/// accepted line the user chose and never enters the companion session,
/// journey, memory, defaults or cross-platform schemas.
struct MapHandoffDraft: Equatable, Identifiable, Sendable {
    let id: String
    let originalText: String
}

/// Lets the user inspect and narrow the text before Map receives it.
///
/// Accepting still does not search. Map opens its existing disclosed search
/// sheet with this text prefilled, and only that sheet's Search action may make
/// an Apple Maps request.
struct MapHandoffPreviewSheet: View {
    @Bindable var model: AppModel
    let draft: MapHandoffDraft

    private var canOpenMap: Bool {
        !model.mapHandoffQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(String(localized: "只带搜索文字"), systemImage: "hand.raised")
                        .font(.headline)

                    Text(String(localized: "只会把你确认的搜索文字带到地图；聊天记录、当前位置和记忆都不会随行。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "原聊天内容"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(draft.originalText)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "地图搜索文字"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            String(localized: "搜索地点或地址"),
                            text: $model.mapHandoffQuery,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    }

                    Text(String(localized: "确认后，地图会打开搜索页并预填这段文字；在你点击搜索前，不会向 Apple 地图发送请求。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "带到地图"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { model.rejectMapHandoff() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.acceptMapHandoff()
                } label: {
                    Label(String(localized: "打开地图搜索"), systemImage: "map.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!canOpenMap)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
