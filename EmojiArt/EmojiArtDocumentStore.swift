//
//  EmojiArtDocumentStore.swift
//  EmojiArt
//
//  Created by CS193p Instructor on 5/6/20.
//  Copyright © 2020 Stanford University. All rights reserved.
//

import SwiftUI
import Combine

class EmojiArtDocumentStore: ObservableObject
{
    let name: String
    
    func name(for document: EmojiArtDocument) -> String {
        if documentNames[document] == nil {
            documentNames[document] = "Untitled"
        }
        return documentNames[document]!
    }
    
    func setName(_ name: String, for document: EmojiArtDocument) {
        if let url = directory?.appendingPathComponent(name) {
            // TODO: "Untitled" and "Untitled " works?
            // TODO: add alert when rename is already in use
            if !documentNames.values.contains(name) {
                removeDocument(document)
                document.url = url
                documentNames[document] = name
            }
        } else {
            documentNames[document] = name
        }
    }
    
    var documents: [EmojiArtDocument] {
        documentNames.keys.sorted { documentNames[$0]! < documentNames[$1]! }
    }
    
    func addDocument(named name: String = "Untitled") {
        let uniqueName = name.uniqued(withRespectTo: documentNames.values)
        let document: EmojiArtDocument
        if let url = directory?.appendingPathComponent(uniqueName) {
            document = EmojiArtDocument(url: url)
        } else {
            document = EmojiArtDocument()
        }
        documentNames[document] = uniqueName
    }

    func removeDocument(_ document: EmojiArtDocument) {
        if let name = documentNames[document], let url = directory?.appendingPathComponent(name) {
            // do nothing if cant delete
            try? FileManager.default.removeItem(at: url)
        }
        documentNames[document] = nil
    }
    
    @Published private var documentNames = [EmojiArtDocument:String]()
    
    private var autosave: AnyCancellable?
    
    init(named name: String = "Emoji Art") {
        self.name = name
        let defaultsKey = "EmojiArtDocumentStore.\(name)"
        documentNames = Dictionary(fromPropertyList: UserDefaults.standard.object(forKey: defaultsKey))
        autosave = $documentNames.sink { names in
            UserDefaults.standard.set(names.asPropertyList, forKey: defaultsKey)
        }
    }

    // points to where all our documents stored
    private var directory: URL?

    init(directory: URL) {
        self.name = directory.lastPathComponent
        self.directory = directory // works with any directory passed into it
        // read contents of directory
        do {
            let documents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            print("documents: \(documents)")
            // for each document in directory
            // create an EmojiArtDocument from constructed directory path to this document (i.e. directory_path + document_name)
            for document in documents {
                print("document: \(directory.appendingPathComponent(document))")
                let emojiArtDocument = EmojiArtDocument(url: directory.appendingPathComponent(document))
                // store in documents
                self.documentNames[emojiArtDocument] = document
            }
        } catch {
            print("EmojiArtDocumentStore: couldn't create store from directory \(directory): \(error.localizedDescription)")
        }
    }
}

extension Dictionary where Key == EmojiArtDocument, Value == String {
    var asPropertyList: [String:String] {
        var uuidToName = [String:String]()
        for (key, value) in self {
            uuidToName[key.id.uuidString] = value
        }
        return uuidToName
    }
    
    init(fromPropertyList plist: Any?) {
        self.init()
        let uuidToName = plist as? [String:String] ?? [:]
        for uuid in uuidToName.keys {
            self[EmojiArtDocument(id: UUID(uuidString: uuid))] = uuidToName[uuid]
        }
    }
}
