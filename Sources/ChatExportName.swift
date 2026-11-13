import Foundation

enum ChatExportName {
    static func timeSuffix(for archive: URL) -> String {
        if let history = readHistory(from: archive), let range = messageTimeRange(in: history) {
            return range
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = formatter.string(from: Date())
        return timestamp + "--" + timestamp
    }

    static func messageTimeRange(in history: String) -> String? {
        let pattern = /^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?$/
        let normalized = history.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var timestamps: [String] = []
        for index in lines.indices.dropFirst() where index + 1 < lines.count {
            guard index == 1 || (index >= 3 && lines[index - 2].isEmpty),
                  !lines[index - 1].isEmpty,
                  !lines[index + 1].isEmpty,
                  let match = lines[index].wholeMatch(of: pattern),
                  let month = Int(match.output.2), (1...12).contains(month),
                  let day = Int(match.output.3), (1...31).contains(day),
                  let hour = Int(match.output.4), (0...23).contains(hour),
                  let minute = Int(match.output.5), (0...59).contains(minute)
            else { continue }
            timestamps.append(String(format: "%@-%02d-%02d_%02d%02d", String(match.output.1),
                                     month, day, hour, minute))
        }
        guard let first = timestamps.min(), let last = timestamps.max() else { return nil }
        return first + "--" + last
    }

    static func filename(from value: String) -> String? {
        var stem = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".zip") { stem.removeLast(4) }
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        stem = stem.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        guard !stem.isEmpty else { return nil }
        while stem.utf8.count > 200 { stem.removeLast() }
        return stem + ".zip"
    }

    private static func readHistory(from archive: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, "Chat History.txt", "聊天记录.txt"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let handle = output.fileHandleForReading
        defer {
            try? handle.close()
            process.waitUntilExit()
        }
        // Only read the transcript, and limit how much a shared archive can expand.
        let limit = 4 * 1024 * 1024
        var data = Data()
        while data.count <= limit {
            guard let chunk = try? handle.read(upToCount: min(65536, limit + 1 - data.count)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= limit else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
