//
//  KBTar.swift
//  KBTar
//
//  Created by Keith Blount on 16/09/2021.
//

import Foundation

internal struct KBTar {
    
    static let blockSize = 512
    
    struct Header {
        
        static let namePosition = 0
        static let nameSize = 100
        static let permissionPosition = 100
        static let permissionsSize = 8
        static let uidPosition = 108
        static let uidSize = 8
        static let gidPosition = 116
        static let gidSize = 8
        static let sizePosition = 124
        static let sizeSize = 12
        static let mtimePosition = 136
        static let mtimeSize = 12
        static let checksumPosition = 148
        static let checksumSize = 8
        static let fileTypePosition = 156
        static let fileTypeSize = 1
        static let linkNamePosition = 157
        static let linkNameSize = 100
        
        struct UStar {
            static let magicPosition = 257
            static let magicSize = 6
            static let versionPosition = 263
            static let versionSize = 2
            static let unamePosition = 265
            static let unameSize = 32
            static let gnamePosition = 297
            static let gnameSize = 32
            static let deviceMajorNumberPosition = 329
            static let deviceMajorNumberSize = 8
            static let deviceMinorNumberPosition = 337
            static let deviceMinorNumberSize = 8
            static let prefixPosition = 345
            static let prefixSize = 155
            static let paddingPosition = 500
            static let paddingSize = 12
        }
    }
    
    struct ExtendedHeader {
        // NOTE: There are many more extended header attributes; these
        // are the only ones we currently support.
        var size: Int?
        var path: String?
        var linkPath: String?
        //var creationDate: Date?
        
        init(string: String) {
            let info = Self.dictionaryFromExtendedHeader(string)
            if let sizeStr = info["size"] {
                self.size = Int(sizeStr) ?? 0
            }
            if let path = info["path"] {
                self.path = path
            }
            if let linkPath = info["linkpath"] {
                self.linkPath = linkPath
            }
            // The created date is a custom field we support that is
            // not part of the Tar format. The Tar format allows for
            // arbitrary custom fields in the extended header, but they
            // must start with capital letters, as all-lowercase fields
            // are reserved for future use. Also:
            // "Vendors can add their own keys by prefixing them with an all
            // uppercase vendor name and a period."
            // https://github.com/Keruspe/tar-parser.rs/blob/master/tar.specs
            // UPDATE: This was a nice experiment and works well enough, but
            // it requires adding an extended header for every entry, which is
            // > 512bytes per entry. This can increase the size of the Tar
            // significantly for archives with many files. And seeing as it's
            // not part of the Tar standard anyway, we no longer bother with this.
            /*
            if let createdStr = info["CR.date"] {
                self.creationDate = Self.isoDateFormatter.date(from: createdStr)
            }
             */
        }
        
        init(size: Int? = nil, path: String? = nil, linkPath: String? = nil) {
            self.size = size
            self.path = path
            self.linkPath = linkPath
        }
        
        var string: String? {
            var string = ""
            
            // NOTE: It's up to the caller to decide which values
            // should be included.
            if let size = size, size > 0 {
                string += headerString(field: "size", value: String(size))
            }
            
            if let path = path, path.isEmpty == false {
                string += headerString(field: "path", value: path)
            }
            
            if let linkPath = linkPath, linkPath.isEmpty == false {
                string += headerString(field: "linkpath", value: linkPath)
            }
            
            // Note that we use UTF-8 to encode the link path and path:
            // https://www.systutorials.com/docs/linux/man/5-star/
            if string.isEmpty == false {
                string = headerString(field: "hdrcharset", value: "ISO-IR 10646 2000 UTF-8") + string
            }
            
            // Use our custom field to record the creation date if necessary.
            /*
            if let creationDate = creationDate {
                string += headerString(field: "CR.date", value: Self.isoDateFormatter.string(from: creationDate))
            }
             */
            
            return string.isEmpty ? nil : string
        }
        
        // Each line of an extended header looks like this:
        //  25 ctime=1084839148.1212\n
        // Where "25" is the count of characters in the line, including the
        // count and the newline.
        private func headerString(field: String, value: String) -> String {
            let valueCount = Data(value.utf8).count
            return countString(field: field, valueCount: valueCount) + " \(field)=\(value)\n"
        }
        
        // Based on calculateCountString(...) from SWCompression.
        private func countString(field: String, valueCount: Int) -> String {
            // Note: we can just use count for the field rather than utf8 count
            // because we know that fields don't use special characters.
            let fixedCount = 3 + field.count + valueCount // 3 = " " + "=" + "\n"
            // Get the current count as a string, not yet including the count itself.
            var countStr = String(fixedCount)
            // Deal with cases where number of digits in count increases when
            // the count itself is included.
            var done = false
            var lengthOfCount = countStr.count
            while done == false {
                // How long with the string be including the count?
                let totalCount = fixedCount + lengthOfCount
                // But wait, is the length of the count including itself longer
                // than before we included it?
                if String(totalCount).count > lengthOfCount {
                    // If so, update the count to the total count. We then
                    // have to carry on the loop, in case this updated count
                    // bumps up the length yet again.
                    countStr = String(totalCount)
                    lengthOfCount = countStr.count
                } else {
                    // Otherwise, we are done.
                    countStr = String(totalCount)
                    done = true
                }
            }
            return countStr
        }
        
        private static func dictionaryFromExtendedHeader(_ string: String) -> [String: String] {
            var info: [String: String] = [:]
            let lines = string.components(separatedBy: .newlines)
            for line in lines {
                // Find elements.
                if let spaceRange = line.range(of: " "),
                   let equalsRange = line.range(of: "=", range: spaceRange.upperBound..<line.endIndex) {
                    let field = line[spaceRange.upperBound..<equalsRange.lowerBound]
                    let value = line[equalsRange.upperBound..<line.endIndex]
                    info[String(field)] = String(value)
                }
            }
            return info
        }
        
        /*
        private static let isoDateFormatter: ISO8601DateFormatter = {
            return ISO8601DateFormatter()
        }()
         */
    }
    
    enum TarType: String {
        // From Wikipedia:
        /*
         '0' or (ASCII NUL)    Normal file
         '1'    Hard link
         '2'    Symbolic link
         '3'    Character special
         '4'    Block special
         '5'    Directory
         '6'    FIFO
         '7'    Contiguous file
         'g'    Global extended header with meta data (POSIX.1-2001)
         'x'    Extended header with meta data for the next file in the archive (POSIX.1-2001)
         'A'–'Z'    Vendor specific extensions (POSIX.1-1988)
         All other values    Reserved for future standardization
         */
        case nullBlock = ""
        case normalFile = "0"
        case hardLink = "1"
        case symbolicLink = "2"
        case characterSpecial = "3"
        case blockSpecial = "4"
        case directory = "5"
        case FIFO = "6"
        case contiguousFile = "7"
        case globalExtendedHeader = "g"
        case extendedHeader = "x"
        case other = "_oThEr" // Not part of Tar spec.
        
        init(resourceValues: URLResourceValues) {
            if resourceValues.isDirectory ?? false {
                self = .directory
            } else if resourceValues.isAliasFile ?? false {
                self = .symbolicLink
            } else {
                self = .normalFile
            }
        }
        
        init(fileAttributes: KBFileAttributes) {
            switch fileAttributes.fileType {
            case .directory:
                self = .directory
            case .symbolicLink, .alias:
                self = .symbolicLink
            default:
                self = .normalFile
            }
        }
        
        var fileTypeIndicator: UInt8 {
            // Return ASCII codes.
            switch self {
            case .normalFile:
                return 48 // "0"
            case .hardLink:
                return 49 // "1"
            case .symbolicLink:
                return 50 // "2"
            case .characterSpecial:
                return 51 // "3"
            case .blockSpecial:
                return 52 // "4"
            case .directory:
                return 53 // "5"
            case .FIFO:
                return 54 // "6"
            case .contiguousFile:
                return 55 // "7"
            case .globalExtendedHeader:
                return 103 // "g"
            case .extendedHeader:
                return 120 // "x"
            default:
                return 0
            }
        }
    }
}
