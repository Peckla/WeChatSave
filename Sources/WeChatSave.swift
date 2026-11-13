import SwiftUI

@main
struct WeChatSave: App {
    var body: some Scene {
        Window("WeChatSave", id: "instructions") {
            VStack(alignment: .leading, spacing: 14) {
                Text("WeChatSave").font(.title2.bold())
                Text("在微信中多选聊天记录，依次选择「合并转发」「转发到其他应用」和「Save WeChat ZIP」。")
                Text("首次分享时选择保存目录并勾选「记住此目录」。之后可直接保存，也可在分享窗口更改目录。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 390, alignment: .leading)
        }
        .windowResizability(.contentSize)
    }
}
