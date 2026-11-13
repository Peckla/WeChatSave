import AppKit

@objc(WeChatSaveShareViewController)
final class ShareViewController: NSViewController {
    private let conversationKey = "LastConversationName"
    private let bookmarkKey = "ExportDirectoryBookmark"
    private var didStart = false

    private var suggestedDirectory: URL {
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Documents/DevMesh/Personal/Projects/WechatSave/Export", isDirectory: true)
    }

    override func loadView() {
        let label = NSTextField(labelWithString: "正在读取微信分享的 ZIP…")
        label.alignment = .center
        view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 85))
        preferredContentSize = view.frame.size
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart, let context = extensionContext else { return }
        didStart = true
        Task {
            do {
                try await receiveAndSave(from: context)
                context.completeRequest(returningItems: nil)
            } catch {
                let alert = NSAlert(error: error)
                _ = await show(alert)
                context.cancelRequest(withError: error)
            }
        }
    }

    private func receiveAndSave(from context: NSExtensionContext) async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let providers = context.inputItems.compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        var attachments: [ZIPAttachment] = []
        for provider in providers {
            if let zip = try? await ZIPAttachment.load(from: provider, into: temporaryDirectory) {
                attachments.append(zip)
            }
        }
        guard !attachments.isEmpty else { throw ZIPError.unreadableAttachment }

        let savedDirectory = resolveDirectory()
        let batch = attachments
        let suffix = await Task.detached(priority: .userInitiated) {
            batch.map { ChatExportName.timeSuffix(for: $0.url) }
        }.value

        let alert = NSAlert()
        alert.messageText = "Save WeChat ZIP"
        if let savedDirectory {
            alert.informativeText = savedDirectory.path
        }
        let conversation = NSTextField(string: UserDefaults.standard.string(forKey: conversationKey) ?? "")
        conversation.placeholderString = "群名或会话名（可选）"
        conversation.setAccessibilityLabel("群名或会话名")
        let filename = NSTextField(string: "")
        filename.setAccessibilityLabel("文件名")
        let fields = NSStackView(views: attachments.count == 1 ? [conversation, filename] : [conversation])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 8
        for field in fields.views {
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true
        }
        alert.accessoryView = fields

        func defaultStem(for timestamp: String) -> String {
            let name = conversation.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.isEmpty ? "微信聊天" : name) + "_" + timestamp
        }

        filename.placeholderString = defaultStem(for: suffix[0])
        if savedDirectory != nil {
            alert.addButton(withTitle: "保存")
        }
        alert.addButton(withTitle: "选择目录…")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        while true {
            let response = await show(alert)
            let useSavedDirectory = savedDirectory != nil && response == .alertFirstButtonReturn
            let chooseDirectory = response == (savedDirectory == nil ? .alertFirstButtonReturn : .alertSecondButtonReturn)
            guard useSavedDirectory || chooseDirectory else { return }

            if attachments.count == 1,
               !filename.stringValue.isEmpty,
               ChatExportName.filename(from: filename.stringValue) == nil {
                alert.informativeText = "请输入有效的文件名。"
                continue
            }
            let named = attachments.enumerated().map { index, attachment in
                let entered = attachments.count == 1 && !filename.stringValue.isEmpty
                    ? filename.stringValue : defaultStem(for: suffix[index])
                return ZIPAttachment(url: attachment.url, name: ChatExportName.filename(from: entered) ?? attachment.name)
            }
            if useSavedDirectory, let savedDirectory, savedDirectory.startAccessingSecurityScopedResource() {
                defer { savedDirectory.stopAccessingSecurityScopedResource() }
                if FileManager.default.isWritableFile(atPath: savedDirectory.path) {
                    try await save(named, to: savedDirectory)
                    rememberConversation(conversation.stringValue)
                    return
                }
            }
            if try await chooseDirectoryAndSave(named, suggested: savedDirectory ?? suggestedDirectory) {
                rememberConversation(conversation.stringValue)
                return
            }
        }
    }

    private func rememberConversation(_ name: String) {
        UserDefaults.standard.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: conversationKey)
    }

    private func chooseDirectoryAndSave(_ attachments: [ZIPAttachment], suggested: URL) async throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Save WeChat ZIP"
        panel.message = "选择 ZIP 的保存目录"
        panel.prompt = "保存到此处"
        panel.directoryURL = suggested
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        let remember = NSButton(checkboxWithTitle: "记住此目录", target: nil, action: nil)
        remember.state = .on
        remember.sizeToFit()
        panel.accessoryView = remember

        let response = await withCheckedContinuation { continuation in
            if let window = view.window {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        guard response == .OK, let selected = panel.url else { return false }
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        let bookmark = remember.state == .on
            ? try selected.bookmarkData(options: .withSecurityScope)
            : nil
        try await save(attachments, to: selected)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        return true
    }

    private func resolveDirectory() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &isStale
        ), !isStale else { return nil }
        return url
    }

    private func save(_ attachments: [ZIPAttachment], to directory: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            for attachment in attachments {
                _ = try attachment.save(to: directory)
            }
        }.value
    }

    private func show(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = view.window {
            return await alert.beginSheetModal(for: window)
        } else {
            return alert.runModal()
        }
    }
}
