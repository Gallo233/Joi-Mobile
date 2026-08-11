import SwiftUI

struct MapExperienceView: View {
    let characterName: String

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.teal.opacity(0.25), Color.blue.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Label("已缓存的文化步行", systemImage: "figure.walk")
                        .font(.headline)
                    Spacer()
                    Label("离线可用", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("路线预览")
                            .font(.title3.bold())
                        Text("可沿已下载路线前进；离线时无法规划新路线。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()
                HStack {
                    Label(characterName, systemImage: "sparkles")
                    Spacer()
                    Button("查看来源") {}
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 82)
            .accessibilityElement(children: .contain)
        }
    }
}
