import AppKit
import Foundation

/// Writes a single clip to a user-chosen Obsidian vault as a Markdown note.
///
/// SANCTIONED PLAINTEXT EXIT. This is one of only two paths that move clip
/// content *out* of the encrypted store on purpose (the other is snippet
/// export). Everything written here lands on disk unencrypted, inside the
/// user's vault, by explicit user action. Keep that invariant visible: do not
/// quietly widen what this writes, and never log clip content.
///
/// Pure local file I/O — no network, no `obsidian://` dependency for the write.
/// Fully unit-testable against a temporary directory.
enum ObsidianExportService {
    struct Options: Sendable {
        var vaultURL: URL
        var subfolder: String
        var filenameTemplate: String
        var includeFrontmatter: Bool
        var fenceNonMarkdown: Bool

        init(
            vaultURL: URL,
            subfolder: String = "ClipySecure",
            filenameTemplate: String = "{date} {title}",
            includeFrontmatter: Bool = true,
            fenceNonMarkdown: Bool = true
        ) {
            self.vaultURL = vaultURL
            self.subfolder = subfolder
            self.filenameTemplate = filenameTemplate
            self.includeFrontmatter = includeFrontmatter
            self.fenceNonMarkdown = fenceNonMarkdown
        }
    }

    enum ExportError: Error {
        case emptyContent
        case attachmentEncodingFailed
    }

    /// Exports `clip` (which must already be decrypted) into the vault. Returns
    /// the URL of the note written. Never overwrites an existing note or
    /// attachment — collisions get a ` (2)`, ` (3)`… suffix.
    @discardableResult
    static func export(_ clip: ClipItem, options: Options) throws -> URL {
        let fileManager = FileManager.default
        let noteDirectory = options.subfolder.isEmpty
            ? options.vaultURL
            : options.vaultURL.appendingPathComponent(options.subfolder, isDirectory: true)
        try fileManager.createDirectory(at: noteDirectory, withIntermediateDirectories: true)

        let baseName = fileName(for: clip, template: options.filenameTemplate)
        let noteURL = uniqueURL(in: noteDirectory, baseName: baseName, extension: "md")

        // Build the body (and any attachment that must accompany it).
        let body = try body(for: clip, noteBaseName: noteURL.deletingPathExtension().lastPathComponent, in: noteDirectory, options: options)

        var document = ""
        if options.includeFrontmatter {
            document += frontmatter(for: clip)
        }
        document += body
        if !document.hasSuffix("\n") { document += "\n" }

        try Data(document.utf8).write(to: noteURL, options: .atomic)
        return noteURL
    }

    // MARK: - Body

    private static func body(
        for clip: ClipItem,
        noteBaseName: String,
        in noteDirectory: URL,
        options: Options
    ) throws -> String {
        // 1. Image → PNG attachment + embed.
        if let imageData = clip.imageData {
            guard let png = pngData(from: imageData) else { throw ExportError.attachmentEncodingFailed }
            let name = try writeAttachment(png, baseName: noteBaseName, extension: "png", in: noteDirectory)
            return "![[\(name)]]"
        }
        // 2. PDF → attachment + embed.
        if let pdfData = clip.pdfData {
            let name = try writeAttachment(pdfData, baseName: noteBaseName, extension: "pdf", in: noteDirectory)
            return "![[\(name)]]"
        }
        // 3. URL(s) → Markdown links.
        let urls = clip.decodedURLs()
        if !urls.isEmpty {
            if urls.count == 1 {
                return "[\(urls[0])](\(urls[0]))"
            }
            return urls.map { "- [\($0)](\($0))" }.joined(separator: "\n")
        }
        // 4. Filenames → bullet list of paths.
        let filenames = clip.decodedFilenames()
        if !filenames.isEmpty {
            return filenames.map { "- `\($0)`" }.joined(separator: "\n")
        }
        // 5. Text / RTF → body, optionally fenced when it is not Markdown.
        if let text = clip.stringValue, !text.isEmpty {
            if options.fenceNonMarkdown, !MarkdownDetector.looksLikeMarkdown(text) {
                return "```\n\(text)\n```"
            }
            return text
        }
        throw ExportError.emptyContent
    }

    // MARK: - Frontmatter

    private static func frontmatter(for clip: ClipItem) -> String {
        var lines = ["---"]
        lines.append("created: \(ISO8601DateFormatter().string(from: clip.createdAt))")
        if let app = clip.sourceAppId, !app.isEmpty {
            lines.append("source_app: \(app)")
        }
        lines.append("tags: [clipysecure]")
        lines.append("type: \(clip.primaryType)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n"
    }

    // MARK: - Filenames

    /// Renders the filename template. `{date}` → ISO `YYYY-MM-DD`, `{title}` →
    /// the clip title with path-hostile characters stripped.
    static func fileName(for clip: ClipItem, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: clip.createdAt)
        let title = sanitize(clip.title)
        var name = template
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{title}", with: title)
        name = sanitize(name)
        return name.isEmpty ? "Untitled" : name
    }

    /// Strips characters that are illegal or awkward in a file name and
    /// collapses whitespace.
    private static func sanitize(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = raw
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func uniqueURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) (\(counter))")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private static func writeAttachment(
        _ data: Data,
        baseName: String,
        extension ext: String,
        in noteDirectory: URL
    ) throws -> String {
        let attachmentsDirectory = noteDirectory.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let url = uniqueURL(in: attachmentsDirectory, baseName: baseName, extension: ext)
        try data.write(to: url, options: .atomic)
        return url.lastPathComponent
    }

    private static func pngData(from imageData: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: imageData) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
