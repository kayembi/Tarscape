//
//  KBTarEntry.swift
//  KBTarEntry
//
//  Created by Keith Blount on 21/09/2021.
//

import Foundation

// Use a class rather than a struct as we need reference semantics
// when storing this in a dictionary.
public class KBTarEntry {
    
    public var name = ""
    public var subpath = ""
    public var entryType = EntryType.file
    public var modificationDate: Date?
    public var fileSize = 0
    public var _realRegularFileContents: Data? // Files only.
    public var fileLocation: UInt64 = 0 // Files only.
    public var tarURL: URL? // Files only.
    public var symbolicLinkDestinationURL: URL? // Symbolic links only.
    public var children: [KBTarEntry] = [] // Directories only.
    private var childrenByName: [String: KBTarEntry] = [:] // Directories only. Key is the child's name.
    
    init(fileWithSubpath subpath: String, regularFileContents: Data, modificationDate: Date?, fileSize: Int) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self._realRegularFileContents = regularFileContents
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.entryType = .file
    }
    
    init(symbolicLinkWithSubpath subpath: String, destination: URL?) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self.symbolicLinkDestinationURL = destination
        self.entryType = .symbolicLink
    }
    
    init(directoryWithSubpath subpath: String, modificationDate: Date?) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self.modificationDate = modificationDate
        self.entryType = .directory
    }
    
    init(lazyFileWithSubpath subpath: String, tarURL: URL, location: UInt64, modificationDate: Date?, fileSize: Int) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self.tarURL = tarURL
        self.fileLocation = location
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.entryType = .file
    }
    
    public func addChild(_ childEntry: KBTarEntry) {
        if entryType == .directory {
            children.append(childEntry)
            childrenByName[childEntry.name] = childEntry
        }
    }
    
    public func child(forName name: String) -> KBTarEntry? {
        return childrenByName[name]
    }
    
    public var descendants: [KBTarEntry] {
        var descendants: [KBTarEntry] = []
        for child in children {
            descendants.append(child)
            if child.entryType == .directory {
                descendants.append(contentsOf: child.descendants)
            }
        }
        return descendants
    }
    
    public func regularFileContents() -> Data? {
        if let _realRegularFileContents = _realRegularFileContents {
            return _realRegularFileContents
        }
        if entryType != .file {
            return nil
        }
        // If we created a lazy file, then we only load the data when regularFileContents()
        // is called for the first time.
        if let tarURL = tarURL {
            if FileManager.default.fileExists(atPath: tarURL.path) == false {
                return nil
            }
            if let fileHandle = try? FileHandle(forReadingFrom: tarURL) {
                try? fileHandle.seek(toOffset: fileLocation)
                _realRegularFileContents = try? fileHandle.read(upToCount: fileSize)
                try? fileHandle.close()
                return _realRegularFileContents
            }
        }
        
        return nil
    }
    
    public enum EntryType: Int {
        case file = 0
        case directory = 1
        case symbolicLink = 2
    }
    
    private static func nameForSubpath(_ subpath: String) -> String {
        return URL(fileURLWithPath: subpath).lastPathComponent
    }
    
    internal static func cleanedSubpath(_ subpath: String) -> String {
        var subpath = subpath
        if subpath.hasPrefix("/") { subpath = String(subpath.dropFirst()) }
        if subpath.hasSuffix("/") { subpath = String(subpath.dropLast()) }
        return subpath
    }
}
