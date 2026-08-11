import SwiftUI

struct ChatStageView: View {
    let characterName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(characterName)
                        .font(.title2.bold())
                    Text("本地会话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("个人面板", systemImage: "person.crop.circle") {}
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)

            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.55), .purple.opacity(0.25), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 58, weight: .light))
                        .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                    Text("原生角色舞台")
                        .font(.title3.weight(.semibold))
                    Text("Live2D / VRM 原生运行时通过验证前，将显示静态角色回退。")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Joi 角色舞台，空闲")
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                TextField("给 Joi 发消息", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                Button("按住说话", systemImage: "mic.fill") {}
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo, in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 82)
        }
        .padding(.top, 14)
    }
}
