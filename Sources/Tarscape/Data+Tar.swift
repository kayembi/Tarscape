//
//  Data+Tar.swift
//  Data+Tar
//
//  Created by Keith Blount on 20/09/2021.
//  Based on code from SWCompression:
//  Copyright (c) 2021 Timofey Solomko
//  Licensed under MIT License

import Foundation

internal extension Data {
    
    /// Appends the string as data, either truncated or padded with zeroed bytes to match
    /// the passed-in `length`.
    ///
    /// - Returns: The size of the original data before it was truncated or padded.
    mutating func append(tarString string: String?, length: Int) {
        guard let string = string else {
            // No value: fill with zeroed bytes.
            self.append(Data(count: length))
            return
        }
        var strData = Data(string.utf8)
        // Ensure the string data is the right length.
        strData.fixTarBlockLength(length)
        self.append(strData)
    }
    
    // Returns prefix data if the name was longer than 100 chars.
    mutating func append(tarName name: String?) -> (prefixData: Data, needsExtendedHeader: Bool) {
        // If the name is nil, just append zeroed-byte data
        // and return zero data for the prefix too.
        guard let name = name else {
            self.append(Data(count: KBTar.Header.nameSize))
            return (prefixData: Data(count: KBTar.Header.UStar.prefixSize), needsExtendedHeader: false)
        }
        
        var needsExtendedHeader = false
        var nameData: Data!
        nameData = name.data(using: .ascii, allowLossyConversion: false)
        if nameData == nil {
            // If we couldn't encode the data as ASCII without losing data,
            // we'll need an extended header.
            needsExtendedHeader = true
            // Fall back on UTF-8 for the name in the main header, even though
            // that's against the specs, otherwise we have to leave it blank
            // which isn't ideal.
            nameData = Data(name.utf8)
        }
        
        var prefixData: Data!
        
        // UStar and pax formats contain a prefix field for long subpaths.
        // This field can be up to 155 bytes, extending the maximum subpath
        // length from 100 to 255.
        // From https://github.com/Keruspe/tar-parser.rs/blob/master/tar.specs:
        /*
         prefix   First part of pathname.  If the pathname is too long to fit in
                  the 100 bytes provided by the standard format, it can be split at
                  any / character with the first portion going here.  If the prefix
                  field is not empty, the reader will prepend the prefix value and
                  a / character to the regular name field to obtain the full path-
                  name.
         */
        var didSplit = false
        if nameData.count > KBTar.Header.nameSize {
            // Get the first forward slash after len - 100.
            // This allows us to use the maximum length for "name"
            // and the rest for "prefix". (If we just search backwards
            // for a forwards slash, we might have been able to fit more
            // in "name", because we might be able to fit more than one
            // path component in "name", which allows for 100 bytes.)
            let forwardSlash = Data("/".utf8) // Or Data([0x2f])
            // NOTE: Add one to the header size (100 + 1 = 101), because
            // if the file name is exactly 100 characters and there is
            // a slash just before it, we can still split it.
            // (We also need to check that the prefix isn't too big.)
            if let slashRange = nameData.range(of: forwardSlash, in: nameData.endIndex-(KBTar.Header.nameSize+1)..<nameData.endIndex),
               slashRange.lowerBound <= KBTar.Header.UStar.prefixSize {
                
                // Split our name data into a prefix and the rest of it.
                prefixData = nameData.prefix(slashRange.lowerBound)
                // Pad to full prefix length.
                prefixData!.fixTarBlockLength(KBTar.Header.UStar.prefixSize)
                
                // Must only update this after extracting prefix from it, of course!
                nameData = nameData.suffix(from: slashRange.upperBound)
                didSplit = true
            }
            // If there's no slash in the last 101 chars, we cannot split the name and create a prefix.
            // Likewise if there was a slash but the prefix would be bigger than the max prefix size.
        }
        
        if prefixData == nil {
            // Return zeroed-byte prefix data if we can't create a prefix.
            prefixData = Data(count: KBTar.Header.UStar.prefixSize)
        }
        
        // If we couldn't split the name and the name is longer than the max name size
        // in the header, we'll need an extended header to store it.
        // NOTE: We must check this before truncating the nameData below.
        if needsExtendedHeader == false && didSplit == false {
            needsExtendedHeader = nameData.count > KBTar.Header.nameSize
        }
        
        // Truncate or pad to correct size.
        nameData.fixTarBlockLength(KBTar.Header.nameSize)
        self.append(nameData)
        
        return (prefixData: prefixData, needsExtendedHeader: needsExtendedHeader)
    }
    
    // This is taken straight from SWCompression.
    mutating func append(tarInt value: Int?, length: Int) {
        // No value: fill with zeroed bytes.
        guard var value = value else {
            self.append(Data(count: length))
            return
        }
        
        // Numeric values can be stored as octals (which allow a maximum encoded file size
        // of 8gb) or they can be base base-256 for bigger sizes. Which encoding is used
        // is determined by the leftmost byte. We need to determine whether we can store the
        // passed-in number as an octal. If it can, we store it as an octal, otherwise we have
        // to store it as base-256. (Older tar formats support octal only, so we prefer octal
        // where possible.)
        let maxOctalValue = Int(tarMaxOctalValueForFieldLength: length)
        
        guard value > maxOctalValue || value < 0 else {
            // Instead of creating a string and grabbing data from that, as SWCompression does,
            // calculate the bytes required for our octal number directly. This should be faster.
            // Normal octal encoding.
            //var octalData = Data(String(value, radix: 8).utf8)
            //octalData.fixTarBlockLength(length)
            //self.append(octalData)
            self.append(contentsOf: Self.octalTarBytes(value: value, length: length))
            return
        }

        // Base-256 encoding.
        // As long as we have at least 8 bytes for our value, conversion to base-256
        // will always succeed, since (64-bit) Int.max neatly fits into 8 bytes of
        // 256-base encoding. (And tar number lengths are all above 8 - 8 or 12 usually.)
        assert(length >= 8 && Int.bitWidth <= 64)
        var buffer = Array(repeating: 0 as UInt8, count: length)
        for i in stride(from: length - 1, to: 0, by: -1) {
            buffer[i] = UInt8(truncatingIfNeeded: value & 0xFF)
            value >>= 8
        }
        buffer[0] |= 0x80 // Highest bit indicates base-256 encoding.
        self.append(Data(buffer))
    }
    
    private static func octalTarBytes(value: Int, length: Int) -> [UInt8] {
        // This is how we convert to Octal:
        // https://www.tutorialspoint.com/how-to-convert-decimal-to-octal
        // 1. Take decimal number as dividend.
        // 2. Divide this number by 8 (8 is base of octal so divisor here).
        // 3. Store the remainder in an array (it will be: 0, 1, 2, 3, 4, 5, 6 or 7
        //    because of divisor 8).
        // 4. Repeat the above two steps until the number is greater than zero.
        // 5. Print the array in reverse order (which will be equivalent octal number
        //    of given decimal number).
        var bytes: [UInt8] = []
        var num = value
        var cnt = 0
        // Continue for as long as we haven't consumed the entire number or for
        // as long as we haven't filled the passed-in length.
        while num > 0 && cnt < length {
            let remainder = num % 8
            num /= 8
            // "0" is ASCII decimal 48, 1 is 49 and so on. So we can easily convert
            // our digit to ASCII by appending 48.
            bytes.insert(UInt8(remainder + 48), at: 0)
            cnt += 1
        }
        // If we overflowed - the passed-in number was too big to convert to an octal
        // number of the given length - just return an array full of ASCII 7s, which
        // is the maximum octal number of the given length.
        if num > 0 {
            // ASCII "7" = decimal 55.
            bytes = Array(repeating: 55, count: length)
        } else if cnt < length {
            // If the length passed in is longer than needed to create the
            // octal number, pad with null characters.
            bytes.append(contentsOf: Array(repeating: 0, count: length - cnt))
        }
        
        return bytes
    }
    
    /// If the `self` is bigger than the passed-in length, it gets truncated. If shorter,
    /// zeroed bytes are added to pad it out.
    private mutating func fixTarBlockLength(_ length: Int) {
        let currentLength = self.count
        if length < currentLength {
            self = self.prefix(upTo: length)
        } else if length > currentLength {
            self.append(Data(count: length - currentLength))
        }
    }
}
