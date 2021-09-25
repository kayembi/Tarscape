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
    
    public enum EntryType: Int {
        case file = 0
        case directory = 1
        case symbolicLink = 2
    }
    
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
    
    // MARK: - Initialisers
    
    internal init(fileWithSubpath subpath: String, regularFileContents: Data, modificationDate: Date?, fileSize: Int) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self._realRegularFileContents = regularFileContents
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.entryType = .file
    }
    
    internal init(symbolicLinkWithSubpath subpath: String, destination: URL?) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self.symbolicLinkDestinationURL = destination
        self.entryType = .symbolicLink
    }
    
    internal init(directoryWithSubpath subpath: String, modificationDate: Date?) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self.modificationDate = modificationDate
        self.entryType = .directory
    }
    
    internal init(lazyFileWithSubpath subpath: String, tarURL: URL, location: UInt64, modificationDate: Date?, fileSize: Int) {
        self.name = Self.nameForSubpath(subpath)
        self.subpath = Self.cleanedSubpath(subpath)
        self.tarURL = tarURL
        self.fileLocation = location
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.entryType = .file
    }
    
    internal func addChild(_ childEntry: KBTarEntry) {
        if entryType == .directory {
            children.append(childEntry)
            childrenByName[childEntry.name.lowercased()] = childEntry
        }
    }
    
    // MARK: - Public Methods
    
    /// Returns the child with the passed-in name.
    ///
    /// The name check is case-insensitive.
    public func child(forName name: String) -> KBTarEntry? {
        return childrenByName[name.lowercased()]
    }
    
    /// Returns the descedant at the given subpath.
    ///
    /// Note that the subpath should be relative to the entry, not to the Tar archive as a whole.
    public func descendant(atSubpath subpath: String) -> KBTarEntry? {
        let subpath = Self.cleanedSubpath(subpath)
        let components = subpath.components(separatedBy: "/")
        var parent = self
        var entry: KBTarEntry?
        for name in components {
            entry = parent.child(forName: name)
            if entry == nil {
                return nil
            }
            parent = entry!
        }
        return entry
    }
    
    /// Subscript version of `descendant(atSubpath:)`.
    public subscript(subpath: String) -> KBTarEntry? {
        return descendant(atSubpath: subpath)
    }
    
    /// Returns an array of all `KBTarEntry` descendants of the entry.
    ///
    /// The array will always be empty for non-directory entries.
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
    
    /// Returns the data for .file entries.
    ///
    /// If the entry was loaded lazily, this methods reads the data from the Tar archive before returning it.
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
    
    /// Writes the file or directory to disk.
    ///
    /// For directory entries, all descendants are also written to disk.
    public func write(to url: URL, atomically: Bool = false) throws {
        switch self.entryType {
            
        case .file:
            try regularFileContents()?.write(to: url, options: atomically ? .atomic : [])
            if let modificationDate = modificationDate {
                try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
            }
            
        case .symbolicLink:
            if let symbolicLinkDestinationURL = symbolicLinkDestinationURL {
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: symbolicLinkDestinationURL)
            } else {
                throw KBTarError.couldNotCreateSymbolicLink
            }
            
        case .directory:
            var attrs: [FileAttributeKey: Any]?
            if let modificationDate = modificationDate {
                attrs = [.modificationDate: modificationDate]
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: attrs)
            // Create all descendants recursively.
            for child in children {
                let childURL = url.appendingPathComponent(child.name)
                try child.write(to: childURL, atomically: atomically)
            }
        }
    }
    
    // Private Methods
    
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
