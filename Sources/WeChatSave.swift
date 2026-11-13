import SwiftUI

@main
struct WeChatSave: App {
    var body: some Scene {
        Window("WeChatSave", id: "instructions") {
            VStack(alignment: .leading, spacing: 14) {
                Text("从微信保存 ZIP")
                    .font(.headline)
                Text("多选聊天记录 → 合并转发 → 转发到其他应用 → Save WeChat ZIP")
                    .fixedSize(horizontal: false, vertical: true)
                Text("首次分享时选择保存目录。勾选「记住此目录」，下次即可直接保存。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 350, alignment: .leading)
            .padding(24)
        }
        .windowResizability(.contentSize)
    }
}
