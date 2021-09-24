//
//  FileManager+Attributes.swift
//  TarCrashTest
//
//  Created by Keith Blount on 22/09/2021.
//
//  NSFileManager's attributesOfItem(atPath:) is *slow*.
//  See:
//  https://github.com/danielamitay/iOS-App-Performance-Cheatsheet/blob/master/Foundation.md
//  "When attempting to retrieve an attribute of a file on disk, using –[NSFileManager attributesOfItemAtPath:error:] will expend an excessive amount of time fetching additional attributes of the file that you may not need. Instead of using NSFileManager, you can directly query the file properties using stat."

import Foundation

/// A much faster alternative to using FileManager's `attributesOfItem(atPath:)`.
///
/// This  grabs the `fileSystemRepresentation` of
/// the passed-in URL and then uses `stat()` to get the attributes.
public struct KBFileAttributes {
    
    public let fileSize: Int
    public let fileType: FileType
    /// The modification date as a Unix value - time interval since 1970.
    public let modificationDateTimeSince1970: TimeInterval
    /// The creation date as a Unix value - time interval since 1970
    public let creationDateTimeSince1970: TimeInterval
    public let ownerAccountID: Int
    public let groupOwnerAccountID: Int
    public let permissions: Int
    
    public init(fileURL: URL, supportAliasFiles: Bool = false) {
        
        let fileSystemRep = FileManager.default.fileSystemRepresentation(withPath: fileURL.path)
        var fileStat = stat()
        lstat(fileSystemRep, &fileStat)
        
        // Alias files are different from symbolic links, and C's stat() mode cannot
        // check for them. We therefore have to use resource values to check for this,
        // which is slower (we thus make it optional).
        var isAlias = false
        if supportAliasFiles {
            isAlias = (try? fileURL.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false
        }
        
        // File type.
        self.fileType = isAlias ? .alias : FileType(mode: fileStat.st_mode)
        
        // File size.
        self.fileSize = Int(fileStat.st_size)
        
        // Modification date.
        let modTimeSpec = fileStat.st_mtimespec
        self.modificationDateTimeSince1970 = TimeInterval(modTimeSpec.tv_sec) + TimeInterval(modTimeSpec.tv_nsec)/1000000000.0
         
        // Creation date.
        let createTimeSpec = fileStat.st_birthtimespec
        self.creationDateTimeSince1970 = TimeInterval(createTimeSpec.tv_sec) + TimeInterval(createTimeSpec.tv_sec)/1000000000.0
         
        // Owner account ID.
        self.ownerAccountID = Int(fileStat.st_uid)
         
        // Group account ID.
        self.groupOwnerAccountID = Int(fileStat.st_gid)
        
        // Permissions.
        // See: https://man7.org/linux/man-pages/man7/inode.7.html
        // Permissions are set as octals.
        // r = octal 4, w = 2, x = 1
        // These are then added up, e.g. r+w+x = octal 7
        // There are three sets of permission: user, group and other.
        // These are stored in different octal columns. So:
        // - user: r = octal 400, w = 200, x = 100
        // - group: r = octal 40, w = 20, x = 10
        // - other: r = octal 4, w = 20, x = 10
        // The last three octal digits of .st_mode provide the posix
        // permissions, so we just need to drop all other digits.
        self.permissions = Int(fileStat.st_mode) % 0o1000
    }
    
    public enum FileType: Int {
        case file = 0
        case directory = 1
        case symbolicLink = 2
        case alias = 3
        
        // See https://man7.org/linux/man-pages/man7/inode.7.html
        // https://github.com/RubyNative/SwiftRuby/blob/master/Stat.swift
        fileprivate init(mode: mode_t) {
            if (mode & S_IFMT) == S_IFDIR {
                self = .directory
            }
            else if (mode & S_IFMT) == S_IFLNK {
                self = .symbolicLink
            } else {
                self = .file
            }
        }
    }
    
    public var modificationDate: Date? {
        return Date(timeIntervalSince1970: modificationDateTimeSince1970)
    }
    
    public var creationDate: Date? {
        return Date(timeIntervalSince1970: creationDateTimeSince1970)
    }
}

// Aborted. This was an experiment to see if using chmod(), utimes() etc would
// be faster than using FileManager's setAttributes(_:ofItemAtPath:), in the same
// way that using stat() is *far* faster than using attributesOfItem(atPath:).
// Alas, it didn't speed things up at all.
/*
public extension FileManager {
    
    func setFileAttributes(_ fileAttributes: KBFileAttributes, for fileURL: URL) {
        
        let cPath = fileURL.path.cString(using: .utf8)
        
        if let modTime = fileAttributes.modificationDateTimeSince1970 {
            let seconds = Int(modTime)
            let microseconds = Int32(min(1000000, modTime.truncatingRemainder(dividingBy: 1) * 1000000.0))
            let nanoseconds = Int(min(1000000, modTime.truncatingRemainder(dividingBy: 1) * 1000000000.0))
            // We have to set both utimes() and utimesat(), otherwise we end
            // up with a date in 2264!
            var timeVal = timeval()
            timeVal.tv_sec = seconds
            timeVal.tv_usec = microseconds
            utimes(cPath, &timeVal)
            var timeSpec = timespec()
            timeSpec.tv_sec = seconds
            timeSpec.tv_nsec = nanoseconds
            utimensat(0, cPath, &timeSpec, 0)
        }
        
        if let permissions = fileAttributes.permissions {
            chmod(cPath, mode_t(permissions))
        }
    }
}
*/
