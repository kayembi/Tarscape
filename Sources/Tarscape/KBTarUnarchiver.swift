//
//  KBTarUnarchiver.swift
//  KBTarUnarchiver
//
//  Created by Keith Blount on 20/09/2021.
//
//  Based on:
//  - SWCompression by Timofey Solomko (c) 2021.
//  - tarkit (DCTar) by Dalton Cherry (c) 2014.
//  - Light Untar by Mathieu Hausherr Octo Technology (c) 2011.

import Foundation

public class KBTarUnarchiver {
    
    private let tarURL: URL
    private let options: Options
    private var fileHandle: FileHandle!
    private let size: Int
    
    // MARK: - Options
    
    public struct Options: OptionSet {
        public let rawValue: Int

        /// If set, file attributes such as modification dates and permissions will be read from the archive
        /// and applied to extracted files. If not set, file attributes for each extracted file will just use the
        /// defaults (such as today's date).
        ///
        /// Setting `.restoreFileAttributes` can significantly increase extraction time, because
        /// it has to use `FileManager`'s `setAttributes(_ofItemAtPath:)`, which is *slow*.
        public static let restoreFileAttributes = Options(rawValue: 1 << 0)
        
        /// If set, a method for working out file URLs is used that is faster for paths containing no spaces
        /// or special characters.
        ///
        /// Setting `.mostSubpathsCanBeUnescaped` will improve extraction speeds for archives
        /// whose entries all use simple file paths - paths containing no spaces or special characters that
        /// would need escaping in a URL. However, if many entries contain characters that need escaping
        /// in a URL,setting this option will *slow* extraction. Only use this option when you know the Tar
        /// archive contains only simple file paths.
        public static let mostSubpathsCanBeUnescaped = Options(rawValue: 1 << 1)
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    // MARK: - Public Methods
    
    // NOTE: TarKit and Light-Untar both use 100 here.
    // This is multiplied by blockSize to calculate the size of the
    // file chunks held in memory before writing to disk. With only
    // 100 x 512, writing is a little slower in Swift (about 0.1 seconds
    // slower than Obj-C for some reason). But that's a tiny amount of
    // memory anyway with lots of small writes to file. By increasing this
    // to 1024, we write in half megabyte chunks which is still a tiny amount
    // to hold in memory, while reducing file writes and speeding things up
    // by a fraction of a second.
    /// Determines how much memory can be used for each file when reading data from the Tar archive
    /// and writing it to disk.
    ///
    /// To avoid consumuing too much memory for large files, data is read from the archive in chunks. A single
    /// block is 512 bytes. The default value is `10240`, which equates to 5MB (10240 x 512 bytes = 5MB). This means
    /// that a 100MB file will not be read from disk all at once, but in 20 chunks of 5MB each.
    ///
    /// Set to `0` to turn off chunking.
    public var maxBlockLoadInMemory = 10240
    
    /// Creates an unarchiver object ready for extracting the Tar file at the passed-in location.
    /// - Parameter tarURL: The path of the Tar file to extract.
    /// - Parameter options: Options for extracting the data. The default value is `[.restoreFileAttributes]`.
    public init(tarURL: URL, options: Options = [.restoreFileAttributes]) throws {
        self.tarURL = tarURL
        self.options = options
        
        // Get the size of the file we want to extract.
        // This will also be used for the maximum progress.
        let attributes = try FileManager.default.attributesOfItem(atPath: tarURL.path)
        guard let size = attributes[.size] as? Int else {
            throw KBTarError.couldNotGetTarSize
        }
        self.size = size
    }
    
    /// Returns the total amount of data that needs extracting.
    ///
    /// Use in conjunction with `extract(to:progressBody:` to show progress during extraction.
    public var progressCount: Int64 {
        return Int64(size)
    }
    
    /// Extracts the tar at `tarURL` to `dirURL`.
    /// - Parameter to: The path to which to extract the Tar file. A directory will be created at this path containing
    ///     the extracted files.
    /// - Parameter progressBody: A closure with a `(Double, Int64)` tuple parameter representing
    ///     the current progress,  where the `Double` is a fraction (0.0 - 1.0) and the `Int64` is the amount of
    ///     data processed so far (`progressCount` being the total).
    public func extract(to dirURL: URL, progressBody: ((Double, Int64) -> Void)? = nil) throws {
        let fm = FileManager.default
        
        // Remove any existing file at the target path.
        if fm.fileExists(atPath: dirURL.path) {
            try fm.removeItem(at: dirURL)
        }
        // Create the folder.
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        let dirAbsPath = dirURL.absoluteString
        do {
            try openFileHandleAndEnumerateTar(progressBody: progressBody) { subpath, location, size, tarType, extendedHeader, stop in
                
                switch tarType {
                    
                case .normalFile:
                    let fileURL = fileURL(forDirectoryURL: dirURL, directoryAbsoluteString: dirAbsPath, subpath: subpath)
                    if size == 0 {
                        try Data().write(to: fileURL)
                    } else {
                        try writeFileData(to: fileURL, at: location + UInt64(KBTar.blockSize), size: size)
                    }
                    // Set file attributes.
                    // NOTE: This is *slow*, so it's optional.
                    if options.contains(.restoreFileAttributes) {
                        let attrs = attributes(at: location)
                        if attrs.isEmpty == false {
                            try? fm.setAttributes(attrs, ofItemAtPath: fileURL.path)
                        }
                    }
                    
                case .directory:
                    let directoryURL = fileURL(forDirectoryURL: dirURL, directoryAbsoluteString: dirAbsPath, subpath: subpath)
                    try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                    if options.contains(.restoreFileAttributes) {
                        let attrs = attributes(at: location)
                        if attrs.isEmpty == false {
                            try? fm.setAttributes(attrs, ofItemAtPath: directoryURL.path)
                        }
                    }
                    
                case .symbolicLink:
                    if let linkName = try? linkName(at: location, extendedHeader: extendedHeader) {
                        let fileURL = fileURL(forDirectoryURL: dirURL, directoryAbsoluteString: dirAbsPath, subpath: subpath)
                        try fm.createSymbolicLink(at: fileURL, withDestinationURL: URL(fileURLWithPath: linkName))
                        // Symbolic links contain no data - just the link name in the header.
                        // Can't set modification date on a symbolic link.
                    }
                    
                default:
                    break // Do nothing - handled by enumerator.
                }
            }
        } catch {
            // Clean up before throwing.
            try? fm.removeItem(at: dirURL)
            throw error
        }
    }
    
    // MARK: - Find an Entry
    
    // These properties are only non-nil if loadAllEntries(lazily:) has been called.
    private var cachedEntries: [String: KBTarEntry]?
    
    /// If `loadAllEntries(lazily:)` has been called, returns all root entries in the Tar archive
    /// as `KBTarEntry` objects.
    public var rootEntries: [KBTarEntry]?
    
    /// Returns the Tar entry at the given subpath, represented by a `KBTarEntry` object.
    ///
    /// If you plan on finding multiple entries using this method, you should first call
    /// `loadAllEntires(lazily:)`, which will cache an internal list of all entries for
    /// use with this method. Otherwise, this method parses through the Tar file data to find
    /// the entry.
    /// - Parameter subpath: The subpath of the entry in Tar file.
    /// - Parameter useLazyLoading: If set to `true`, the returned entry will not load
    ///     its data from the Tar file until `regularFileContents()` is called on the entry.
    ///     Otherwise, the data is loaded into memory immediately.
    public func entry(atSubpath findSubpath: String, useLazyLoading: Bool = false) throws -> KBTarEntry? {
        
        // If we've pre-loaded all of the entries, just grab the entry
        // from there.
        if let cachedEntries = cachedEntries {
            return cachedEntries[KBTarEntry.cleanedSubpath(findSubpath)]
        }
        
        var foundEntry: KBTarEntry?
        let lowerFindSubpath = KBTarEntry.cleanedSubpath(findSubpath).lowercased() // Case-insensitive.
        // Get a directory version of the path with a slash appended to it, which we use
        // for checking when searching for descendants.
        let lowerFindDirPath = lowerFindSubpath + (lowerFindSubpath.hasSuffix("/") ? "" : "/")
        var gatherDescendants = false
        var parentEntriesBySubpath: [String: KBTarEntry] = [:]
        
        try openFileHandleAndEnumerateTar(progressBody: nil) { subpath, location, size, tarType, extendedHeader, stop in
            
            // First check to see if this is a match.
            let lowerSubpath = KBTarEntry.cleanedSubpath(subpath).lowercased() // Case-insensitive.
            
            // If we don't already have a match, check to see if this is it.
            var isMatch = false
            if gatherDescendants == false {
                isMatch = lowerSubpath == lowerFindSubpath
            } else { // We've already found a directory match and are gathering descendants.
                // If we're set to gather descendants because the found item is a
                // directory, then check the passed-in path is the first part
                // of the current path, indicating the current path is a descendant
                // of the folder we're looking for.
                if lowerSubpath.hasPrefix(lowerFindDirPath) == false {
                    gatherDescendants = false
                    // Stop the search.
                    stop = true
                }
            }
            
            if isMatch || gatherDescendants  {
                
                switch tarType {
                    
                case .normalFile:
                    let entry: KBTarEntry
                    let modDate = try? modificationDate(at: location)
                    // If set to use lazy loading, don't load file data into memory until the
                    // it's asked for by the user invoking regularFileContents().
                    if useLazyLoading {
                        entry = KBTarEntry(lazyFileWithSubpath: subpath, tarURL: tarURL, location: location, modificationDate: modDate, fileSize: size)
                    } else {
                        let data = try self.data(at: location, length: size)
                        entry = KBTarEntry(fileWithSubpath: subpath, regularFileContents: data, modificationDate: modDate, fileSize: size)
                    }
                    // If this is the exact match, we can stop looking (regular
                    // files don't have descendants).
                    if isMatch {
                        foundEntry = entry
                        stop = true
                    } else {
                        // Must be gathering descendants.
                        if let parentEntry = Self.parentEntry(ofSubpath: subpath, in: parentEntriesBySubpath) {
                            parentEntry.addChild(entry)
                        }
                    }
                    
                case .directory:
                    let modDate = try? modificationDate(at: location)
                    let entry = KBTarEntry(directoryWithSubpath: subpath, modificationDate: modDate)
                    // If this is the exact match, record it and then look for descendants
                    // on subsequent passes.
                    if isMatch {
                        foundEntry = entry
                        gatherDescendants = true
                        parentEntriesBySubpath[KBTarEntry.cleanedSubpath(subpath)] = entry
                    } else {
                        // Must be gathering descendants.
                        if let parentEntry = Self.parentEntry(ofSubpath: subpath, in: parentEntriesBySubpath) {
                            parentEntry.addChild(entry)
                        }
                        // Record all folders so that we can look them up and add
                        // files as children to them.
                        parentEntriesBySubpath[KBTarEntry.cleanedSubpath(subpath)] = entry
                    }
                    
                case .symbolicLink:
                    let linkName = try? linkName(at: location, extendedHeader: extendedHeader)
                    let linkURL = linkName != nil ? URL(fileURLWithPath: linkName!) : nil
                    let entry = KBTarEntry(symbolicLinkWithSubpath: subpath, destination: linkURL)
                    // If this is the exact match, we can stop looking (symbolic
                    // links don't have descendants).
                    if isMatch {
                        foundEntry = entry
                        stop = true
                    } else {
                        // Must be gathering descendants.
                        if let parentEntry = Self.parentEntry(ofSubpath: subpath, in: parentEntriesBySubpath) {
                            parentEntry.addChild(entry)
                        }
                    }
                
                default:
                    break
                }
            }
        }
        
        return foundEntry
    }
    
    /// Loads all `KBTarEntry` objects into memory.
    ///
    /// Call this method before calling `entry(atSubpath:)` or using subscript to find an entry if you intend
    /// to search for more than one entry. If you don't call this first, each call to `entry(atSubpath:)`
    /// will open and parse the Tar file, which will be considerably slower.
    ///
    /// If you only need to find a single entry, just use `entry(atSubpath:)` without calling
    /// `loadAllEntries()` first.
    /// - Parameter lazily: If set to `true`, file entries will not load their data into memory until
    ///     `regularFileContents()` is called on the entry.
    public func loadAllEntries(lazily: Bool = true) throws {
        var cachedEntries: [String: KBTarEntry] = [:]
        var rootEntries: [KBTarEntry] = []
        
        try openFileHandleAndEnumerateTar(progressBody: nil) { subpath, location, size, tarType, extendedHeader, stop in
            
            switch tarType {
                
            case .normalFile:
                let entry: KBTarEntry
                let modDate = try? modificationDate(at: location)
                // If set to use lazy loading, don't load file data into memory until the
                // it's asked for by the user invoking regularFileContents().
                if lazily {
                    entry = KBTarEntry(lazyFileWithSubpath: subpath, tarURL: tarURL, location: location, modificationDate: modDate, fileSize: size)
                } else {
                    let data = try self.data(at: location, length: size)
                    entry = KBTarEntry(fileWithSubpath: subpath, regularFileContents: data, modificationDate: modDate, fileSize: size)
                }
                
                // Add as a child to parent entries.
                if let parentEntry = Self.parentEntry(ofSubpath: subpath, in: cachedEntries) {
                    parentEntry.addChild(entry)
                } else {
                    // If it had no parent, it must be a root entry.
                    rootEntries.append(entry)
                }
                // And cache.
                cachedEntries[KBTarEntry.cleanedSubpath(subpath)] = entry
                
            case .directory:
                let modDate = try? modificationDate(at: location)
                let entry = KBTarEntry(directoryWithSubpath: subpath, modificationDate: modDate)
                if let parentEntry = Self.parentEntry(ofSubpath: subpath, in: cachedEntries) {
                    parentEntry.addChild(entry)
                } else {
                    rootEntries.append(entry)
                }
                cachedEntries[KBTarEntry.cleanedSubpath(subpath)] = entry
                
            case .symbolicLink:
                let linkName = try? linkName(at: location, extendedHeader: extendedHeader)
                let linkURL = linkName != nil ? URL(fileURLWithPath: linkName!) : nil
                let entry = KBTarEntry(symbolicLinkWithSubpath: subpath, destination: linkURL)
                if let parentEntry = Self.parentEntry(ofSubpath: subpath, in: cachedEntries) {
                    parentEntry.addChild(entry)
                } else {
                    rootEntries.append(entry)
                }
                cachedEntries[KBTarEntry.cleanedSubpath(subpath)] = entry
            
            default:
                break
            }
        }
        
        self.cachedEntries = cachedEntries
        self.rootEntries = rootEntries
    }
    
    /// Subscript version of `entry(atSubpath:)`.
    public subscript(subpath: String) -> KBTarEntry? {
        return try? entry(atSubpath: subpath)
    }
    
    private static func parentEntry(ofSubpath subpath: String, in entriesBySubpath: [String: KBTarEntry]) -> KBTarEntry? {
        // First get the parent's subpath by deleting the last path component from
        // the passed-in subpath. (We could use URL's deletingLastPathComponent here,
        // but we want to tidy things up a little more and that will return a path
        // to the user's home directory if there is no parent folder.)
        var parentSubpath = subpath
        if parentSubpath.hasSuffix("/") {
            parentSubpath = String(parentSubpath.dropLast())
        }
        if let slashRange = parentSubpath.range(of: "/", options: .backwards) {
            parentSubpath = String(parentSubpath[parentSubpath.startIndex..<slashRange.lowerBound])
        } else {
            parentSubpath = ""
        }
        if parentSubpath.hasPrefix("/") {
            parentSubpath = String(parentSubpath.dropFirst())
        }
        return entriesBySubpath[parentSubpath]
    }
    
    // MARK: - Main Enumeration Method
    
    // This is used both by the directory creation method and by the entry finding method.
    private func openFileHandleAndEnumerateTar(progressBody: ((Double, Int64) -> Void)? = nil, entryBlock:(String, UInt64, Int, KBTar.TarType, KBTar.ExtendedHeader?, inout Bool) throws -> Void) throws {
        let fm = FileManager.default
        // Check the Tar file exists.
        guard fm.fileExists(atPath: tarURL.path) else {
            throw KBTarError.tarFileDoesNotExist
        }
        
        // Create a file handle for reading the Tar file.
        fileHandle = try FileHandle(forReadingFrom: tarURL)
        
        // Position in the file.
        var location: UInt64 = 0
        var keepGoing = true
        
        // Extended headers are regular entries with a header and data that appear
        // direclty before the entries they modify.
        var nextExtendedHeader: KBTar.ExtendedHeader?
        
        while location < size && keepGoing {
            var blockCount = 1 // 1 block for the header (each block = 512 bytes).
            
            // Update the progress.
            // For this we pass both the fraction completed and
            // the current location (Progress requires us to work
            // with absolutes rather than fractions.)
            progressBody?(Double(location)/Double(size), Int64(location))
            
            try autoreleasepool { // Keep memory tidy.
                let type = try type(at: location)
                
                // Grab the extended header if the last entry was one.
                // Then clear the cached extended header for the next pass.
                // (An extended header is a regular entry with its own header, which
                // overrides header information in the entry that follows it.)
                let extendedHeader = nextExtendedHeader
                nextExtendedHeader = nil
                
                var name: String?
                var size = 0
                
                switch type {
                    
                case .normalFile:
                    name = try self.name(at: location, extendedHeader: extendedHeader)
                    size = try fileSize(at: location, extendedHeader: extendedHeader)
                    if size > 0 {
                        // Get the number of 512 blocks used for this data (Tar data is
                        // always written in multiples of 512 bytes, with zero-byte padding at
                        // the end). Round up - the last block will be padded.
                        // (Subtract 1 from size before dividing to ensure we will be one
                        // block short, so that adding the extra block is right even if we
                        // started with an exact multiple of 512.)
                        blockCount += ((size - 1) / KBTar.blockSize) + 1
                    }
                    
                case .directory:
                    name = try self.name(at: location, extendedHeader: extendedHeader)
                    // No need to increment block count as directories contain no data, just a header.
                    
                case .symbolicLink:
                    name = try self.name(at: location, extendedHeader: extendedHeader)
                    
                case .nullBlock:
                    break // Do nothing.
                    
                case .extendedHeader:
                    // An extended header cannot itself have an extended header,
                    // so pass in nil for the header here.
                    let size = try fileSize(at: location, extendedHeader: nil)
                    if size > 0 {
                        // We grab the extended header that will affect the next entry.
                        nextExtendedHeader = try self.extendedHeader(at: location, length: size)
                        blockCount += ((size - 1) / KBTar.blockSize) + 1
                    }
                    
                    // Not a file or directory?
                case .hardLink, .characterSpecial, .blockSpecial, .FIFO, .contiguousFile, .globalExtendedHeader:
                    // Unsupported block - just skip over it.
                    let size = try fileSize(at: location, extendedHeader: extendedHeader)
                    blockCount += ((size - 1) / KBTar.blockSize) + 1
                    
                case .other: // Unknown type - throw an error.
                    throw KBTarError.invalidTarType
                }
                
                // We only call the block for types we need to make files or get data for.
                // (i.e. Only those we have a name for.)
                if let name = name {
                    var stop = false
                    try entryBlock(name, location, size, type, extendedHeader, &stop)
                    keepGoing = !stop
                }
            }
            
            location += UInt64(blockCount * KBTar.blockSize)
        }
        
        // Ensure progress finishes.
        progressBody?(1.0, progressCount)
        
        // We've finished with the file handle - close it to finish.
        try fileHandle.close()
    }
    
    // MARK: - Fast URL Construction
    
    // URL.appendingPathComponent() is *slow*, presumably because it has to check
    // whether it needs to escape various characters. So we have an optional setting
    // that allows us to construct URLs in a way that is twice as fast. However, this
    // faster method will fail if the subpath contains any spaces or special characters,
    // in which case we have to fall back on the standard URL.appending method. So the
    // special option should only be used when we know that the archive doesn't contain
    // paths with special characters.
    private func fileURL(forDirectoryURL dirURL: URL, directoryAbsoluteString: String, subpath: String) -> URL {
        if options.contains(.mostSubpathsCanBeUnescaped),
           let fileURL = URL(string: directoryAbsoluteString + "/" + subpath) {
            return fileURL
        }
        return dirURL.appendingPathComponent(subpath)
    }
    
    // MARK: - Private Helper Methods
    
    // NOTE: The name is really the subpath.
    private func name(at offset: UInt64, extendedHeader: KBTar.ExtendedHeader?) throws -> String {
        
        // If there's a path in the exended header that comprised the previous entry,
        // that overides the name in the current header. (The extended header allows
        // any path length.)
        if let extendedHeader = extendedHeader,
           let extendedPath = extendedHeader.path,
           extendedPath.isEmpty == false {
            return extendedPath
        }
        
        let name = try string(at: offset, position: KBTar.Header.namePosition, length: KBTar.Header.nameSize)
        
        // Longer names may be split into a prefix and name.
        let prefix = try string(at: offset, position: KBTar.Header.UStar.prefixPosition, length: KBTar.Header.UStar.prefixSize)
        if prefix.isEmpty == false {
            var subpath = prefix
            if subpath.hasSuffix("/") == false && name.hasPrefix("/") == false {
                subpath += "/"
            }
            subpath += name
            return subpath
        }
        
        return name
    }
    
    private func linkName(at offset: UInt64, extendedHeader: KBTar.ExtendedHeader?) throws -> String {
        // If there's a link name in the extended header that comprised the previous entry,
        // that overrides anything in the current header. (The extended header allows any
        // length of link.)
        if let extendedHeader = extendedHeader,
           let linkPath = extendedHeader.linkPath,
           linkPath.isEmpty == false {
            return linkPath
        }
        
        // NOTE: We don't currently support symbolic links of more than 100 characters.
        return try string(at: offset, position: KBTar.Header.linkNamePosition, length: KBTar.Header.linkNameSize)
    }
    
    private func fileSize(at offset: UInt64, extendedHeader: KBTar.ExtendedHeader?) throws -> Int {
        // If there's a size in the extended header that comprised the previous entry,
        // that overrides the size in the current header. Extended headers allow for files
        // of any size and aren't limited to the 8gb size of the octal size in older tars.
        // (Although we can encode as base-256 in the regular tar, so this isn't so important.)
        if let extendedHeader = extendedHeader,
           let extendedSize = extendedHeader.size,
           extendedSize > 0 {
            return extendedSize
        }
        return try tarInt(at: offset, position: KBTar.Header.sizePosition, length: KBTar.Header.sizeSize)
    }
    
    private func type(at offset: UInt64) throws -> KBTar.TarType {
        let string = try string(at: offset, position: KBTar.Header.fileTypePosition, length: KBTar.Header.fileTypeSize)
        return KBTar.TarType(rawValue: string) ?? .other
    }
    
    private func extendedHeader(at offset: UInt64, length: Int) throws -> KBTar.ExtendedHeader {
        // The extended header data is a normal entry after a normal header length.
        let string = try string(at: offset, position: KBTar.blockSize, length: length)
        return KBTar.ExtendedHeader(string: string)
    }
    
    // MARK: - File Attributes
    
    private func attributes(at offset: UInt64) -> [FileAttributeKey: Any] {
        var attrs: [FileAttributeKey: Any] = [:]
        if let modDate = try? modificationDate(at: offset) {
            attrs[.modificationDate] = modDate
        }
        if let permissions = try? permissions(at: offset) {
            attrs[.posixPermissions] = permissions
        }
        if let uid = try? uid(at: offset) {
            attrs[.ownerAccountID] = uid
        }
        if let gid = try? gid(at: offset) {
            attrs[.groupOwnerAccountID] = gid
        }
        return attrs
    }
    
    private func modificationDate(at offset: UInt64) throws -> Date {
        let since1970 = try tarInt(at: offset, position: KBTar.Header.mtimePosition, length: KBTar.Header.mtimeSize)
        return Date(timeIntervalSince1970: TimeInterval(since1970))
    }
    
    private func modificationTimeInterval(at offset: UInt64) throws -> TimeInterval {
        let since1970 = try tarInt(at: offset, position: KBTar.Header.mtimePosition, length: KBTar.Header.mtimeSize)
        return TimeInterval(since1970)
    }
    
    private func permissions(at offset :UInt64) throws -> Int {
        return try tarInt(at: offset, position: KBTar.Header.permissionPosition, length: KBTar.Header.permissionsSize)
    }
    
    private func uid(at offset: UInt64) throws -> Int {
        return try tarInt(at: offset, position: KBTar.Header.uidPosition, length: KBTar.Header.uidSize)
    }
    
    private func gid(at offset: UInt64) throws -> Int {
        return try tarInt(at: offset, position: KBTar.Header.gidPosition, length: KBTar.Header.gidSize)
    }
    
    // MARK: - Generic Helper Methods
    
    private func string(at offset: UInt64, position: Int, length: Int) throws -> String {
        let data = try data(at: offset + UInt64(position), length: length)
        
        // This is how we convert data to bytes in Swift (there's no .bytes getter).
        // See:
        // https://gorjanshukov.medium.com/working-with-bytes-in-ios-swift-4-de316a389a0c
        // Note that SWCompression does it like this;
        // data.withUnsafeBytes { $0.map { $0 } }
        // That gives the same result, though.
        var byteArray: [UInt8] = [UInt8](data)
        // Must terminate with null character.
        if byteArray.last != 0 {
            byteArray.append(0)
        }
        // This is based on tarCString(maxLength: Int) from SWCompression's
        // LittleEndianByteReader.
        // (I tried String(bytes: byteArray, encoding: .utf8)! but that results in
        // an embedded NUL character.)
        // Apple's documentation in fact says to do it the SWCompression way:
        // https://developer.apple.com/documentation/swift/string/1641523-init
        return byteArray.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
    
    private func tarInt(at offset: UInt64, position: Int, length: Int) throws -> Int {
        // Size is stored as an ASCII string.
        let data = try data(at: offset + UInt64(position), length: length)
        return try Int(tarData: data)
    }
    
    private func data(at location: UInt64, length: Int) throws -> Data {
        try fileHandle.seek(toOffset: location)
        let data = try fileHandle.read(upToCount: length)
        guard let data = data else {
            throw KBTarError.invalidData
        }
        return data
    }
    
    // MARK: - Write Data
    
    private func writeFileData(to fileURL: URL, at location: UInt64, size: Int) throws {
        
        try fileHandle.seek(toOffset: location)
        
        // Max size is the amount of data to hold in memory before writing
        // to disk. This is a balancing act: too many writes to disk slows
        // things down, but so does having too much data in memory.
        let maxReadingSize = 100 * KBTar.blockSize
        
        // If the file we have to write is smaller than the chunk size,
        // or if we have set the chunk size to 0 or less, just read the
        // whole file at once.
        if maxReadingSize <= 0 || size <= maxReadingSize {
            if let data = try fileHandle.read(upToCount: size) {
                try data.write(to: fileURL)
            }
            return
        }
        
        // Otherwise, use a file handle for writing and write in chunks.
        
        // Write an empty file, grab a file handle from it for writing,
        // and then write the data into it.
        // We must not write atomically - that is *very* slow.
        try Data().write(to: fileURL)
        let destinationHandle = try FileHandle(forWritingTo: fileURL)
        var remainingSize = size
        while remainingSize > maxReadingSize {
            // Use an autorelease pool so that we don't consume memory
            // with large files.
            try autoreleasepool {
                if let contents = try fileHandle.read(upToCount: maxReadingSize) {
                    try destinationHandle.write(contentsOf: contents)
                }
                remainingSize -= maxReadingSize
            }
        }
        // Read what's left.
        if remainingSize > 0 {
            try autoreleasepool {
                if let contents = try fileHandle.read(upToCount: remainingSize) {
                    try destinationHandle.write(contentsOf: contents)
                }
            }
        }
        // We've finished writing, so close the file.
        try destinationHandle.close()
    }
}
