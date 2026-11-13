import AppKit

@objc(WeChatSaveShareViewController)
final class ShareViewController: NSViewController, NSTextFieldDelegate {
    private let conversationKey = "LastConversationName"
    private let bookmarkKey = "ExportDirectoryBookmark"
    private var didStart = false
    private let status = NSTextField(labelWithString: "正在读取微信分享的 ZIP…")
    private let conversation = NSTextField(string: "")
    private let filename = NSTextField(string: "")
    private let preview = NSTextField(wrappingLabelWithString: "")
    private var firstSuffix = ""

    private var suggestedDirectory: URL {
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Documents/DevMesh/Personal/Projects/WechatSave/Export", isDirectory: true)
    }

    override func loadView() {
        preferredContentSize = NSSize(width: 360, height: 90)
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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

        firstSuffix = suffix[0]
        try await chooseDirectoryAndSave(attachments, suffixes: suffix, suggested: savedDirectory ?? suggestedDirectory)
    }

    private func defaultStem(for timestamp: String) -> String {
        let name = conversation.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? "微信聊天" : name) + "_" + timestamp
    }

    func controlTextDidChange(_ notification: Notification) {
        updatePreview()
    }

    private func updatePreview() {
        let stem = filename.stringValue.isEmpty ? defaultStem(for: firstSuffix) : filename.stringValue
        preview.stringValue = ChatExportName.filename(from: stem) ?? "请输入有效的文件名。"
    }

    private func chooseDirectoryAndSave(_ attachments: [ZIPAttachment], suffixes: [String], suggested: URL) async throws {
        let panel = NSOpenPanel()
        panel.title = "Save WeChat ZIP"
        panel.message = "选择 ZIP 的保存目录"
        panel.prompt = "保存到此处"
        panel.directoryURL = suggested
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        conversation.stringValue = UserDefaults.standard.string(forKey: conversationKey) ?? ""
        conversation.delegate = self
        conversation.setAccessibilityLabel("会话名")
        filename.delegate = self
        filename.setAccessibilityLabel("自定义文件名")
        filename.placeholderString = "留空使用自动文件名"
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = 2
        preview.lineBreakMode = .byTruncatingMiddle

        let remember = NSButton(checkboxWithTitle: "记住此目录", target: nil, action: nil)
        remember.state = .on
        var rows: [NSView] = [NSTextField(labelWithString: "会话名（可选）"), conversation]
        if attachments.count == 1 {
            rows += [NSTextField(labelWithString: "自定义文件名（可选）"), filename, preview]
            updatePreview()
        }
        rows.append(remember)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        for field in [conversation, filename, preview] where rows.contains(field) {
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        stack.setFrameSize(stack.fittingSize)
        panel.accessoryView = stack
        panel.isAccessoryViewDisclosed = true
        status.stringValue = "请选择保存目录…"

        let response = await withCheckedContinuation { continuation in
            if let window = view.window {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        guard response == .OK, let selected = panel.url else { return }

        let named = try attachments.enumerated().map { index, attachment in
            let stem = attachments.count == 1 && !filename.stringValue.isEmpty
                ? filename.stringValue : defaultStem(for: suffixes[index])
            guard let name = ChatExportName.filename(from: stem) else { throw ZIPError.invalidFilename }
            return ZIPAttachment(url: attachment.url, name: name)
        }
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        try await save(named, to: selected)
        UserDefaults.standard.set(conversation.stringValue, forKey: conversationKey)
        if remember.state == .on {
            if let bookmark = try? selected.bookmarkData(options: .withSecurityScope) {
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
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
        status.stringValue = "正在保存 ZIP…"
        status.isHidden = false
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
