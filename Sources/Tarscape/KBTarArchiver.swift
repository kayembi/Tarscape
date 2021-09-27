//
//  KBTarArchiver.swift
//  KBTarArchiver
//
//  Created by Keith Blount on 20/09/2021.
//
//  Based on:
//  - SWCompression by Timofey Solomko (c) 2021.
//  - tarkit (DCTar) by Dalton Cherry (c) 2014.
//  - Light Untar by Mathieu Hausherr Octo Technology (c) 2011.

import Foundation

public class KBTarArchiver {
    
    private let directoryURL: URL
    private let options: Options
    private var fileHandle: FileHandle!
    
    // MARK: - Options
    
    public struct Options: OptionSet {
        public let rawValue: Int

        /// If set, archiving checks for aliases and stores them as symbolic links in the archive. (The Tar format
        /// doesn't support alias files by default, only symbolic links.) Checking for alias files takes extra time
        /// and so slows the archiving process.
        public static let convertAliasFiles = Options(rawValue: 1 << 0)
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    // MARK: - Public Methods
    
    // Populated if progress count is requested.
    private var allFiles: [URL]?
    private var _progressCount: Int64 = 0
    
    /// Returns the total number of files to be archived.
    ///
    /// Use in conjunction with `archive(to:progressBody:`) to show progress during archiving.
    public var progressCount: Int64 {
        if allFiles != nil {
            return _progressCount
        }
        
        let e = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil)!
        var allFiles: [URL] = []
        for case let fileURL as URL in e {
            allFiles.append(fileURL)
        }
        self.allFiles = allFiles
        self._progressCount = Int64(allFiles.count)
        
        return _progressCount
    }
    
    /// Determines how much memory can be used for each file while copying files from disk into the Tar archive.
    ///
    /// To avoid consumuing too much memory for large files, files are read from disk for archiving in chunks. A single
    /// block is 512 bytes. The default value is `10240`, which equates to 5MB (10240 x 512 bytes = 5MB). This means
    /// that a 100MB file will not be read from disk all at once, but in 20 chunks of 5MB each.
    ///
    /// Set to `0` to turn off chunking.
    public var maxBlockLoadInMemory = 10240 // x 512 = 5MB (i.e. 10kb x 512 = 5MB).
    
    /// Creates a new archiver object ready to generate a Tar file from the passed-in directory contents.
    /// - Parameter directoryURL: The path to the directory for archiving.
    /// - Parameter options: Options for creating the archive. The default value is `[]`.
    public init(directoryURL: URL, options: Options = []) {
        self.directoryURL = directoryURL
        self.options = options
    }
    
    /// Creates a Tar file at `tarURL`.
    /// - Parameter to: The path at which the Tar file should be created.
    /// - Parameter progressBody: A closure with a `(Double, Int64)` tuple parameter representing
    ///     the current progress,  where the `Double` is a fraction (0.0 - 1.0) and the `Int64` is the number of
    ///     files processed so far (`progressCount` being the total).
    public func archive(to tarURL: URL, progressBody: ((Double, Int64) -> Void)? = nil) throws {
        let fm = FileManager.default
        // Check the source file exists.
        guard fm.fileExists(atPath: directoryURL.path) else {
            throw KBTarError.fileNotFound
        }
        
        // Remove any existing file at the target path.
        if fm.fileExists(atPath: tarURL.path) {
            try fm.removeItem(at: tarURL)
        }
        
        // Create an empty file at the target path and open it
        // for reading using a file handle.
        try Data().write(to: tarURL)
        fileHandle = try FileHandle(forWritingTo: tarURL)
        
        let basepath = directoryURL.standardizedFileURL.path
        var basepathLen = basepath.count
        if basepath.hasSuffix("/") == false { basepathLen += 1}
        
        // Do the work in a nested method, so that we can call the same code
        // while handling things slightly differently if we need to show the
        // progress.
        func encode(fileURL: URL) throws {
            try autoreleasepool {
                // Work out the subpath.
                let subpath = String(fileURL.standardizedFileURL.path.dropFirst(basepathLen))
                try encodeBinaryData(for: fileURL, subpath: subpath)
            }
        }
        
        if progressBody != nil {
            // Gather list of all files first so that we can get the count
            // in order to calculate our progress.
            // (If the progress count has already been requested, then
            // allFiles should already have been populated.)
            if self.allFiles == nil {
                let e = fm.enumerator(at: directoryURL, includingPropertiesForKeys: nil)!
                var allFiles: [URL] = []
                for case let fileURL as URL in e {
                    allFiles.append(fileURL)
                }
                self.allFiles = allFiles
            }
            
            let fileCount = Double(allFiles!.count)
            for (i, fileURL) in allFiles!.enumerated() {
                progressBody!(Double(i)/fileCount, Int64(i))
                try encode(fileURL: fileURL)
            }
        } else {
            // If we don't need to show the progress, just do the work as
            // we enumerate through the files.
            let e = fm.enumerator(at: directoryURL, includingPropertiesForKeys: nil)!
            for case let fileURL as URL in e {
                try encode(fileURL: fileURL)
            }
        }
        
        // Ensure progress finishes.
        progressBody?(1.0, _progressCount)
        
        // Append two empty blocks to to indicate the end of the file
        // and then close our file handle - we're done.
        let data = Data(count: KBTar.blockSize * 2)
        try fileHandle.write(contentsOf: data)
        try fileHandle.close()
    }
    
    // MARK: - Private Helper Methods
    
    private func encodeBinaryData(for fileURL: URL, subpath: String) throws {
        
        let fileAttributes = KBFileAttributes(fileURL: fileURL, supportAliasFiles: options.contains(.convertAliasFiles))
        
        // Get the Tar type (directory, symbolic link or regular file).
        //let tarType = KBTar.TarType(resourceValues: resourceValues)
        let tarType = KBTar.TarType(fileAttributes: fileAttributes)
        
        var subpath = subpath
        // Add a slash to directory subpaths.
        if tarType == .directory && subpath.hasSuffix("/") == false {
            subpath += "/"
        }
        
        // Write the header.
        let dataSize = try writeHeader(for: fileURL, subpath: subpath, tarType: tarType, fileAttributes: fileAttributes)
        
        // Write the data for regular files.
        if tarType == .normalFile {
            try writeData(from: fileURL, size: dataSize)
        }
    }
    
    // Returns the expected data file size. (The return value is for use by regular data;
    // extended headers pass the file size in as a parameter.)
    @discardableResult private func writeHeader(for fileURL: URL? = nil, subpath: String? = nil, tarType: KBTar.TarType, fileAttributes: KBFileAttributes? = nil, fileSize: Int = 0) throws -> Int {
        
        // Header is KBTar.blockSize (512 bytes).
        
        // Get file attributes.
        
        // Set default permissions:
        // - 420 (octal 644) for files: rw-r-r (owner can read-write, everyone else read).
        // - 493 (octal 755) for directories: rwxr-xr-x (owner can read-write, everyone else
        //   can read and list contents).
        var permissions: Int?
        var modDateTimeSince1970: TimeInterval?
        var userID: Int?
        var groupUserID: Int?
        var linkName: String?
        var fileSize = max(fileSize, 0) // Should never be negative anyway!
        
        // An extended header itself has a header - it's a regular entry with a header
        // and data that modifies the entrie it precedes. All it should contain in the
        // header, though, is the file size. Everything else should be left zeroed.
        if tarType != .extendedHeader {
            
            permissions = tarType == .directory ? 493 : 420
            
            if let fileAttributes = fileAttributes {
                modDateTimeSince1970 = fileAttributes.modificationDateTimeSince1970
                fileSize = fileAttributes.fileSize
                userID = fileAttributes.ownerAccountID
                groupUserID = fileAttributes.groupOwnerAccountID
                permissions = fileAttributes.permissions
            }
            
            if tarType == .symbolicLink,
               let fileURL = fileURL {
                // Ty to get the destination file.
                if options.contains(.convertAliasFiles) && fileAttributes?.fileType == .alias {
                    // Aliases are slighlty different from symbolic links.
                    linkName = try? URL(resolvingAliasFileAt: fileURL, options: [.withoutUI, .withoutMounting]).path
                } else {
                    linkName = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)
                    if linkName == nil {
                        // If we couldn't resolve the symbolic link, treat it as an alias.
                        linkName = try? URL(resolvingAliasFileAt: fileURL, options: [.withoutUI, .withoutMounting]).path
                    }
                }
            }
        }
        
        // Create the empty data to which we will append the header.
        var data = Data()
        
        // Note that KBTar.Header defines all of the sizes based based on the Tar format.
        // These must be written in the correct order - each piece of information must
        // appear at a specific byte position.
        
        // First comes the name (subpath).
        // Note that this can be a maximum of 100 characters. Our append(tarName:)
        // method returns data to be used in the UStar "prefix" field. (Names longer
        // than 100 characters can be split into a prefix and main name.)
        let nameInfo = data.append(tarName: subpath) // 0 - 100
        
        data.append(tarInt: permissions, length: KBTar.Header.permissionsSize) // 100 - 108
        data.append(tarInt: userID, length: KBTar.Header.uidSize) // 108 - 116
        data.append(tarInt: groupUserID, length: KBTar.Header.gidSize) // 116 - 124
        
        data.append(tarInt: fileSize, length: KBTar.Header.sizeSize) // 124 - 136
        
        if let modDateTimeSince1970 = modDateTimeSince1970 {
            data.append(tarInt: Int(modDateTimeSince1970), length: KBTar.Header.mtimeSize) // 136 - 148
        } else {
            data.append(tarInt: nil, length: KBTar.Header.mtimeSize)
        }
        
        // Checksum is calculated based on the complete header with spaces instead of checksum.
        // (This is replaced at the end of the method, once we have all of the header data
        // in place.)
        data.append(contentsOf: Array(repeating: 0x20, count: KBTar.Header.checksumSize)) // 148 - 156
        
        // 1 byte for the file type.
        data.append(tarType.fileTypeIndicator) // 156 - 157
        
        // This will pad with zeroed bytes if linkName is nil.
        data.append(tarString: linkName, length: KBTar.Header.linkNameSize)
        
        // We use the UStar format, which is the most common,
        // even though it does have limitations (such as a 100-char
        // limit for subpaths and symbolic links).
        // We thus have to add the additional UStar fields.
        // This is the "magic" code that determines this is
        // of the UStar format: u s t a r \0 0 0  at byte offset
        // 257 (for POSIX versions - Wikipedia).
        // This is also used by the newer Pax format (which we support).
        // (Note that this is magic (6 bytes) + version (2 bytes).)
        data.append(contentsOf: [0x75, 0x73, 0x74, 0x61, 0x72, 0x00, 0x30, 0x30]) // "ustar\000" // 257 - 265
        
        // NOTE: We could get the user and group names by querying file attributes,
        // using attributesOfItem(atPath:) and the keys .ownerAccountName and
        // .groupOwnerAccountName. However, attributesOfItem(atPath:) is *slow*,
        // so we just omit this information.
        // User name.
        data.append(tarString: nil, length: KBTar.Header.UStar.unameSize) // 265 - 297
        // Group name.
        data.append(tarString: nil, length: KBTar.Header.UStar.gnameSize) // 297 - 329
        
        // We don't record the device number.
        data.append(tarInt: nil, length: KBTar.Header.UStar.deviceMajorNumberSize) // 329 - 337
        data.append(tarInt: nil, length: KBTar.Header.UStar.deviceMinorNumberSize) // 337 - 345
        
        // Append the subpath prefix data, which we created when adding the name.
        data.append(nameInfo.prefixData) // 345 - 500 (155 chars).
        
        // Pad header data to the full 512 bytes (we should already have encoded 500 bytes).
        data.append(Data(count: KBTar.blockSize-data.count))
        
        // Checksum calculation.
        /*
         checksum
                  Header checksum, stored as an octal number in ASCII.  To compute
                  the checksum, set the checksum field to all spaces, then sum all
                  bytes in the header using unsigned arithmetic.  This field should
                  be stored as six octal digits followed by a null and a space
                  character.  Note that many early implementations of tar used
                  signed arithmetic for the checksum field, which can cause inter-
                  operability problems when transferring archives between systems.
                  Modern robust readers compute the checksum both ways and accept
                  the header if either computation matches.
         */
        // From SWCompression - also see: https://developer.apple.com/forums/thread/110356
        // Sum all bytes in the header.
        let checksum = data.reduce(0) { $0 + Int($1) }
        // SWCompression creates the checksum data by converting the checksum to a 6-digit
        // octal string and then creating ASCII data from that. This is quite slow. We use
        // a custom method to calculate the bytes from the checksum number, which is much
        // faster (4 times faster in testing).
        //let checksumString = String(format: "%06o", checksum).appending("\0 ")
        //data.replaceSubrange(KBTar.Header.checksumPosition..<KBTar.Header.checksumPosition + KBTar.Header.checksumSize, with: checksumString.data(using: .ascii)!)
        data.replaceSubrange(KBTar.Header.checksumPosition..<KBTar.Header.checksumPosition + KBTar.Header.checksumSize, with: checksumBytes(for: checksum))
        
        #if DEBUG
        assert(data.count == 512, "Error: Tar header is not 512 bytes!")
        #endif
        
        // Before appending the header, check to see if we need to add an extended
        // header first. Extended headers are regular entries with their own entry
        // and data, which allow us to encode longer file names and link names. We
        // should also use the extended header if the path or link could not be
        // encoded using UTF-8. (We actually encode "name" and "linkname" above
        // using UTF-8, even though this is against the Tar specs, which states they
        // should be ASCII. But otherwise we have to throw an error or use zero
        // bytes. Tar readers should grab the path from the extended header anyway
        // if it is present. In this, we follow how SWCompression does things.)
        // We also need to use an extended header if we are set to include creation
        // dates. We have to use a custom field in an extended header for that, given
        // that Tar doesn't support encoding creation dates normally.
        var encodePaxLink = false
        if let linkName = linkName {
            let asciiLen = linkName.data(using: .ascii)?.count
            encodePaxLink = asciiLen == nil || asciiLen! > KBTar.Header.linkNameSize
        }
        let encodePaxFileSize = fileSize > Int(tarMaxOctalValueForFieldLength: KBTar.Header.sizeSize)
        if nameInfo.needsExtendedHeader || encodePaxLink || encodePaxFileSize {
            var extendedHeader = KBTar.ExtendedHeader()
            if nameInfo.needsExtendedHeader {
                extendedHeader.path = subpath
            }
            if encodePaxLink {
                extendedHeader.linkPath = linkName
            }
            if encodePaxFileSize {
                extendedHeader.size = fileSize
            }
            do {
                try writeExtendedHeader(extendedHeader)
            } catch {
                throw KBTarError.couldNotCreateExtendedHeader
            }
            // Now that we've appended the special extended header entry,
            // we can carry on and write the regular header.
        }
        
        // Write the header data to our Tar file.
        try? fileHandle.write(contentsOf: data)
        
        // Return the file size.
        return fileSize
    }
    
    // Get the checksum bytes for the header.
    private func checksumBytes(for checksum: Int) -> [UInt8] {
        // The checksum is six bytes representing an octal number terminated
        // by a null and a space.
        // Create the default bytes. The checksum ends with a null byte (ASCII 0)
        // followed by a space (32). We padd the rest with zeroes (ASCII 48).
        var bytes: [UInt8] = [48, 48, 48, 48, 48, 48, 0, 32]
        // This is how we convert to Octal:
        // https://www.tutorialspoint.com/how-to-convert-decimal-to-octal
        // 1. Take decimal number as dividend.
        // 2. Divide this number by 8 (8 is base of octal so divisor here).
        // 3. Store the remainder in an array (it will be: 0, 1, 2, 3, 4, 5, 6 or 7
        //    because of divisor 8).
        // 4. Repeat the above two steps until the number is greater than zero.
        // 5. Print the array in reverse order (which will be equivalent octal number
        //    of given decimal number).
        // We'll build our octal number backwards, so we start by replacing
        // the sixth number in the array (index 5).
        var i = 5
        var num = checksum
        // We don't want to replace any more than 6 bytes, so check i >= 0
        while num > 0 && i >= 0 {
            let remainder = num % 8
            num /= 8
            // "0" is ASCII decimal 48, 1 is 49 and so on. So we can easily convert
            // our digit to ASCII by appending 48.
            bytes[i] = UInt8(remainder + 48)
            i -= 1
        }
        // If after creating 6 digits we haven't finished converting the whole
        // checksum to octal, we've overflowed, so fill the checksum with the
        // max 6-digit octal value.
        if num > 0 {
            // 55 = ASCII descial for 7, terminated by null and space.
            bytes = [55, 55, 55, 55, 55, 55, 0, 32]
        }
        return bytes
    }
    
    private func writeExtendedHeader(_ extendedHeader: KBTar.ExtendedHeader) throws {
        // From https://github.com/Keruspe/tar-parser.rs/blob/master/tar.specs:
        /*
         An entry in a pax interchange format archive consists of one or two stan-
         dard ustar entries, each with its own header and data.  The first
         optional entry stores the extended attributes for the following entry.
         This optional first entry has an "x" typeflag and a size field that indi-
         cates the total size of the extended attributes.  The extended attributes
         themselves are stored as a series of text-format lines encoded in the
         portable UTF-8 encoding.  Each line consists of a decimal number, a
         space, a key string, an equals sign, a value string, and a new line.  The
         decimal number indicates the length of the entire line, including the
         initial length field and the trailing newline.  An example of such a
         field is:
            25 ctime=1084839148.1212\n
         */
        
        // First get the extended header string.
        guard let xString = extendedHeader.string else {
            return // Nothing to write out.
        }
        // And get the data - we will need to record its count.
        let xHeaderData = Data(xString.utf8)
        let dataSize = xHeaderData.count
        
        // Now create the header.
        try writeHeader(tarType: .extendedHeader, fileSize: dataSize)
        
        // And write the data.
        try fileHandle.write(contentsOf: xHeaderData)
        // Add zero pading to fill up the tar block.
        // (Entry sizes must be multiples of 512.)
        let padding = (KBTar.blockSize - (dataSize % KBTar.blockSize)) % KBTar.blockSize
        try fileHandle.write(contentsOf: Data(count: padding))
    }
    
    private func data(from fileURL: URL) throws -> (data: Data, size: Int) {
        var content = try Data(contentsOf: fileURL)
        let contentSize = content.count
        // Blocks must be multiples of 512.
        let padding = (KBTar.blockSize - (contentSize % KBTar.blockSize)) % KBTar.blockSize
        //data.append(content)
        // Add zero padding to fill up the tar block.
        content.append(Data(count: padding))
        
        return (data: content, size: contentSize)
    }
    
    private func writeData(from fileURL: URL, size: Int) throws {
        
        // Entry sizes must be multiples of 512 (blockSize = 512).
        // NOTE: size % blockSize gives us how many bytes will be left
        // over after dividing by 512.
        // blockSize - remainder gives us how much padding we should add.
        // However, if the file size was a multiple of 512, remainder will
        // be 0, so blockSize - 0 will give us 512. Adding 512 zero bytes
        // will mess things up, so we % by blockSize a second time to account
        // for this situation.§
        let padding = (KBTar.blockSize - (size % KBTar.blockSize)) % KBTar.blockSize
        
        // The simplest way of doing this is to grab the data and write it
        // to our file handle.
        // If this file is smaller than the chunk size, or if the chunk size
        // is set to zero or less, just load the file entire.
        let copyChunkSize = maxBlockLoadInMemory * KBTar.blockSize
        
        if copyChunkSize <= 0 || size <= copyChunkSize {
            let content = try Data(contentsOf: fileURL)
            try fileHandle.write(contentsOf: content)
            // Zero pad to 512 multiples.
            try fileHandle.write(contentsOf: Data(count: padding))
            return
        }

        // Otherwise, use a file handle.
        let readingHandle = try FileHandle(forReadingFrom: fileURL)
        var remainingSize = size
        while remainingSize > copyChunkSize {
            try autoreleasepool {
                if let content = try readingHandle.read(upToCount: copyChunkSize) {
                    try fileHandle.write(contentsOf: content)
                }
                remainingSize -= copyChunkSize
            }
        }
        // Copy what's left.
        if remainingSize > 0 {
            try autoreleasepool {
                if let content = try readingHandle.read(upToCount: remainingSize) {
                    try fileHandle.write(contentsOf: content)
                }
            }
        }
        
        // Zero pad to 512 bytes.
        try fileHandle.write(contentsOf: Data(count: padding))
        
        // Close our reading file handle.
        try readingHandle.close()
    }
}
