//
//  KBTarErrors.swift
//  KBTarErrors
//
//  Created by Keith Blount on 20/09/2021.
//

import Foundation

public enum KBTarError: LocalizedError {
    
    case invalidData
    case invalidTarType
    case tarFileDoesNotExist
    case couldNotGetTarSize
    case fileNotFound
    case invalidNumber
    case couldNotCreateExtendedHeader
    case couldNotCreateSymbolicLink
    
    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return KBTarLocalize.string("Could not read data.")
        case .invalidTarType:
            return KBTarLocalize.string("The .tar file contains unsupported elements.")
        case .tarFileDoesNotExist:
            return KBTarLocalize.string("No .tar file exists at the specified path.")
        case .couldNotGetTarSize:
            return KBTarLocalize.string("Coult not get .tar file size.")
        case .fileNotFound:
            return KBTarLocalize.string("There is nothing to archive at the specified path.")
        case .invalidNumber:
            return KBTarLocalize.string("Could not decode number.")
        case .couldNotCreateExtendedHeader:
            return KBTarLocalize.string("Could not create extended header.")
        case .couldNotCreateSymbolicLink:
            return KBTarLocalize.string("Could not create symbolic link.")
        }
    }
    
    /*
    public var recoverySuggestion: String? {
    }
     */
}

fileprivate class KBTarLocalize {
    
    public static func string(_ string: String, comment: String = "") -> String {
        
        // NOTE: value is the string used in the development
        // locale; for other locales it is the string used if
        // the key (the first paramter) isn't found in the
        // table.
        return NSLocalizedString(string, tableName: localizedStringsTable, bundle: frameworkBundle, value: string, comment: comment)
    }
    
    private static let localizedStringsTable = "Localizable"
    
    private static var frameworkBundle: Bundle {
        return Bundle(for: Self.self)
    }
}
