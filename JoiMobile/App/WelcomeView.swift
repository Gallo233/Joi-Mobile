import SwiftUI

/// The one-time welcome (`G2-J5A`).
///
/// PRD §3.2 lists six first-run steps, and this covers the three that are about
/// the product's stance rather than about a screen the user will reach anyway:
/// that everything works without an account, what durable memory means before
/// anything durable can happen, and that permissions are asked at the moment
/// they are used rather than up front.
///
/// It is an overlay with a dismiss, not a page the user has to walk through.
/// §3.2 says first run is complete once a character is visible and a message can
/// be sent — so this must not stand between the user and that, and a test holds
/// it to that.
struct WelcomeView: View {
    let characterName: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("你好，我是 \(characterName)。")
                    .font(.title3.bold())
                Spacer()
                Button(String(localized: "知道了"), action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.indigo)
            }

            point(
                symbol: "iphone",
                title: String(localized: "不需要账号"),
                detail: String(localized: "对话、角色和记忆都存在这台设备上。没有登录，也没有云端同步。")
            )
            point(
                symbol: "bookmark",
                title: String(localized: "记忆需要你点头"),
                detail: String(localized: "聊天内容默认只是当下的上下文。只有你在聊天记录里选中某句话并确认，它才会被长期记住，之后也可以随时删除。")
            )
            point(
                symbol: "hand.raised",
                title: String(localized: "权限用到时才要"),
                detail: String(localized: "麦克风在你第一次按住说话时才请求，位置在你开始步行时才请求。不用这些功能，就什么都不会问你。")
            )

            Text("现在就可以直接给我发消息。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 24, y: 8)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }

    private func point(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.indigo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
