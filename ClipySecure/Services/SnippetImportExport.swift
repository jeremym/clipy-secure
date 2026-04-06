import Foundation
import GRDB

struct SnippetImportExport: Sendable {
    // Clipy XML format:
    // <folders>
    //   <folder>
    //     <title>FolderName</title>
    //     <snippets>
    //       <snippet>
    //         <title>SnippetTitle</title>
    //         <content>SnippetContent</content>
    //       </snippet>
    //     </snippets>
    //   </folder>
    // </folders>

    private static let maxImportFileSize = 10 * 1024 * 1024 // 10 MB

    static func importXML(from url: URL, into dbQueue: DatabaseQueue) throws {
        // Validate file size before parsing
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = attributes[.size] as? Int, fileSize > maxImportFileSize {
            throw ImportExportError.fileTooLarge
        }

        // Parse with XXE protection disabled
        let options: XMLNode.Options = [.nodeLoadExternalEntitiesNever]
        let xmlDoc = try XMLDocument(contentsOf: url, options: options)
        guard let root = xmlDoc.rootElement(), root.name == "folders" else {
            throw ImportExportError.invalidFormat
        }

        let folderElements = root.elements(forName: "folder")

        try dbQueue.write { db in
            for (folderIndex, folderElement) in folderElements.enumerated() {
                let folderTitle = folderElement.elements(forName: "title").first?.stringValue ?? "Untitled Folder"

                let folder = SnippetFolder(title: folderTitle, sortIndex: folderIndex)
                try folder.insert(db)

                if let snippetsElement = folderElement.elements(forName: "snippets").first {
                    let snippetElements = snippetsElement.elements(forName: "snippet")
                    for (snippetIndex, snippetElement) in snippetElements.enumerated() {
                        let snippetTitle = snippetElement.elements(forName: "title").first?.stringValue ?? "Untitled Snippet"
                        let snippetContent = snippetElement.elements(forName: "content").first?.stringValue ?? ""

                        let snippet = Snippet(
                            folderId: folder.id,
                            title: snippetTitle,
                            content: snippetContent,
                            sortIndex: snippetIndex
                        )
                        try snippet.insert(db)
                    }
                }
            }
        }
    }

    static func exportXML(from dbQueue: DatabaseQueue, to url: URL) throws {
        let (folders, allSnippets) = try dbQueue.read { db -> ([SnippetFolder], [Snippet]) in
            let folders = try SnippetFolder
                .order(Column("sortIndex").asc)
                .fetchAll(db)
            let snippets = try Snippet
                .order(Column("sortIndex").asc)
                .fetchAll(db)
            return (folders, snippets)
        }

        let root = XMLElement(name: "folders")
        let xmlDoc = XMLDocument(rootElement: root)

        for folder in folders {
            let folderElement = XMLElement(name: "folder")
            folderElement.addChild(XMLElement(name: "title", stringValue: folder.title))

            let snippetsElement = XMLElement(name: "snippets")
            let folderSnippets = allSnippets.filter { $0.folderId == folder.id }

            for snippet in folderSnippets {
                let snippetElement = XMLElement(name: "snippet")
                snippetElement.addChild(XMLElement(name: "title", stringValue: snippet.title))
                snippetElement.addChild(XMLElement(name: "content", stringValue: snippet.content))
                snippetsElement.addChild(snippetElement)
            }

            folderElement.addChild(snippetsElement)
            root.addChild(folderElement)
        }

        let xmlData = xmlDoc.xmlData(options: [.nodePrettyPrint])
        try xmlData.write(to: url)
    }

    enum ImportExportError: Error, LocalizedError {
        case invalidFormat
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "The file is not a valid Clipy snippets XML file."
            case .fileTooLarge:
                return "The import file exceeds the 10 MB size limit."
            }
        }
    }
}
