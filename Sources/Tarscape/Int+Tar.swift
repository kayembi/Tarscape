//
//  Int+Tar.swift
//  Int+Tar
//
//  Created by Keith Blount on 20/09/2021.
//

import Foundation

internal extension Int {
    
    // Get the maximum number that can be stored by an octal of the given length.
    // The largest number that can be stored with twelve digits, for instance, is
    // 777,777,777,777. But in Tar, only eleven digits can be stored, the twelfth
    // being reserved for a zeroed byte, giving a maximum 77,777,777,777). This is
    // an octal (base 8). Convert that to decimal, and you get 8,589,934,591 - around
    // eight gigabytes. Here's an easy way to get the max value:
    // let str = String(repeating: "7", count: length-1)
    // let maxOctalValue = Int(str, radix: 8)!
    // The below is faster, though (from SWCompression and tarkit). This is based on
    // how an octal number represents three binary digits. (E.g. (1 << 10)-1 would give us
    // 1023, or 1111111111 in binary - the biggest 10-digit binary number. This works because
    // if we bit shift 1 left 10 places, be get binary 10000000000 - an eleven-digit number -
    // and then subtract one to get the highest ten-digit number. One octal digit represents
    // three binary digits, so we multiply the length by three before bit shifting to get
    // the maximum octal number of the given number of digits.)
    // NOTE: Subtract 1 from the length here. The maximum length that can be stored is
    // length - 1 because there must be at least one space or null character after it.
    init(tarMaxOctalValueForFieldLength length: Int) {
        self = (1 << ((length-1) * 3)) - 1
    }
    
    // Based on code from SWCompression.
    init(tarData: Data) throws {
        var byteArray: [UInt8] = [UInt8](tarData)
        // Must terminate with null character.
        if byteArray.last != 0 {
            byteArray.append(0)
        }
        
        // Numbers are usually encoded as octals. However, large numbers can be encoded
        // as base-256 in later versions of the Tar format.
        // Check to see if it uses base-256 encoding.
        // (This base-256 conversion code is taken from SWCompression.)
        // NOTE: No need to check byteArray.isEmpty because we made sure of that above.
        if byteArray[0] & 0x80 != 0 {
            // Inversion mask for handling negative numbers.
            let invMask = byteArray[0] & 0x40 != 0 ? 0xFF : 0x00
            var result = 0
            for i in 0..<byteArray.count {
                var byte = Int(byteArray[i]) ^ invMask
                if i == 0 {
                    byte &= 0x7F // Ignoring bit which indicates base-256 encoding.
                }
                if result >> (Int.bitWidth - 8) > 0 {
                    throw KBTarError.invalidNumber // Integer overflow
                }
                result = (result << 8) | byte
            }
            if result >> (Int.bitWidth - 1) > 0 {
                throw KBTarError.invalidNumber // Integer overflow
            }
            self = invMask == 0xFF ? ~result : result
        }
        
        // If we got here, we have a normal octal encoding.
        let string = byteArray.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        // Size is an octal number; we need to convert to decimal.
        //return strtol(string, nil, 8)
        self = Int(string, radix: 8) ?? 0
    }
}
