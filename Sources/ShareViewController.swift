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
    private var choice: CheckedContinuation<SaveChoice, Never>?
    private var form: NSStackView?
    private let shareSize = NSSize(width: 500, height: 320)

    private enum SaveChoice {
        case save, chooseDirectory, cancel
    }

    private var suggestedDirectory: URL {
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Documents/DevMesh/Personal/Projects/WechatSave/Export", isDirectory: true)
    }

    override func loadView() {
        // The host can size the share window before the attachments finish loading.
        preferredContentSize = shareSize
        view = NSView(frame: NSRect(origin: .zero, size: shareSize))
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
        installForm(savedDirectory: savedDirectory, attachmentCount: attachments.count)
        while true {
            let action = await withCheckedContinuation { choice = $0 }
            guard action != .cancel else { return }
            let useSavedDirectory = action == .save
            if attachments.count == 1,
               !filename.stringValue.isEmpty,
               ChatExportName.filename(from: filename.stringValue) == nil {
                preview.stringValue = "请输入有效的文件名。"
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
            form?.isHidden = true
            status.stringValue = "请选择保存目录…"
            status.isHidden = false
            if try await chooseDirectoryAndSave(named, suggested: savedDirectory ?? suggestedDirectory) {
                rememberConversation(conversation.stringValue)
                return
            }
            status.isHidden = true
            form?.isHidden = false
        }
    }

    private func installForm(savedDirectory: URL?, attachmentCount: Int) {
        conversation.stringValue = UserDefaults.standard.string(forKey: conversationKey) ?? ""
        conversation.delegate = self
        filename.delegate = self
        filename.placeholderString = "留空使用下方的自动文件名"
        conversation.setAccessibilityLabel("群名或会话名")
        filename.setAccessibilityLabel("自定义文件名")
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = 2
        preview.lineBreakMode = .byTruncatingMiddle

        let directory = NSTextField(wrappingLabelWithString: savedDirectory?.path ?? "保存时选择目录")
        directory.textColor = .secondaryLabelColor
        directory.maximumNumberOfLines = 2
        directory.lineBreakMode = .byTruncatingMiddle
        directory.toolTip = savedDirectory?.path
        let choose = NSButton(title: "选择目录…", target: self, action: #selector(chooseFolder))
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelSave))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(saveHere))
        let buttons = NSStackView(views: savedDirectory == nil ? [cancel, choose] : [cancel, choose, save])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        (savedDirectory == nil ? choose : save).keyEquivalent = "\r"

        var rows: [NSView] = [NSTextField(labelWithString: "群名或会话名（可选）"), conversation]
        if attachmentCount == 1 {
            rows += [NSTextField(labelWithString: "自定义文件名（可选）"), filename,
                     NSTextField(labelWithString: "保存文件名"), preview]
            updatePreview()
        } else {
            rows.append(NSTextField(labelWithString: "\(attachmentCount) 个 ZIP 将按各自的聊天时间命名"))
        }
        rows += [NSTextField(labelWithString: "保存位置"), directory, buttons]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        for field in [conversation, filename, preview, directory] where field.superview != nil {
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for row in rows {
            row.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        conversation.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if attachmentCount == 1 {
            filename.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16)
        ])
        status.isHidden = true
        form = stack
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

    @objc private func saveHere() { finishChoice(.save) }
    @objc private func chooseFolder() { finishChoice(.chooseDirectory) }
    @objc private func cancelSave() { finishChoice(.cancel) }

    private func finishChoice(_ value: SaveChoice) {
        let pending = choice
        choice = nil
        pending?.resume(returning: value)
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
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let selected = panel.url else { return false }
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        try await save(attachments, to: selected)
        if remember.state == .on {
            if let bookmark = try? selected.bookmarkData(options: .withSecurityScope) {
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
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
        form?.isHidden = true
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
