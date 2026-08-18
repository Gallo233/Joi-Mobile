import SwiftUI

struct RootShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch model.selectedSurface {
                case .chat:
                    ChatStageView(model: model)
                case .map:
                    MapExperienceView(characterName: model.currentCharacterName, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                SurfaceSwitcher(selection: model.selectedSurface) { surface in
                    withAnimation(.snappy(duration: 0.25)) {
                        model.select(surface)
                    }
                }

                Button {
                    model.presentCharacterLibrary()
                } label: {
                    Image(systemName: "person.2.crop.square.stack.fill")
                        .font(.headline)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("角色库")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .background(Color(.systemGroupedBackground))
        .task { await model.restoreActiveCharacter() }
        .sheet(isPresented: $model.isCharacterLibraryPresented) {
            CharacterLibraryView(model: model)
        }
    }
}

private struct SurfaceSwitcher: View {
    let selection: PrimarySurface
    let onSelect: (PrimarySurface) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button(for: .chat, title: String(localized: "聊天"), symbol: "bubble.left.and.bubble.right.fill")
            button(for: .map, title: String(localized: "地图"), symbol: "map.fill")
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func button(for surface: PrimarySurface, title: String, symbol: String) -> some View {
        Button {
            onSelect(surface)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selection == surface ? Color.white : Color.primary)
                .background(selection == surface ? Color.indigo : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == surface ? .isSelected : [])
    }
}
