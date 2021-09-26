//
//  FileManager+Tar.swift
//  FileManager+Tar
//
//  Created by Keith Blount on 20/09/2021.
//

import Foundation

@objc // Expose this extension to Objective-C.
public extension FileManager {
    
    @nonobjc
    func extractTar(at tarURL: URL, to dirURL: URL, options: KBTarUnarchiver.Options = [.restoresFileAttributes], progressBody: ((Double) -> Void)? = nil) throws {
        try KBTarUnarchiver(tarURL: tarURL, options: options).extract(to: dirURL, progressBody: progressBody)
    }
    
    @nonobjc
    func createTar(at tarURL: URL, from dirURL: URL, options: KBTarArchiver.Options = [], progressBody: ((Double) -> Void)? = nil) throws {
        try KBTarArchiver(directoryURL: dirURL, options: options).archive(to: tarURL, progressBody: progressBody)
    }
    
    // MARK: - Objective-C Compatible Methods
    
    // Swift methods using OptionSet cannot be exposed to Objective-C, so we provide some alternative
    // methods that expose the most useful options.
    
    /// Extracts the tar at `tarURL` to `dirURL`.
    /// - Parameter at: The path of the Tar file to extract.
    /// - Parameter to: The path to which to extract the Tar file. A directory will be created at this path containing the extracted files.
    /// - Parameter restoreAttributes: If `false`, file attributes stored in the archive such as modification dates and file
    ///     permissions be ignored. This can significantly speed up the extraction process.
    /// - Parameter progressBody: A closure with a `Double` parameter representing the current progress (from 0.0 to 1.0).
    @objc(extractTarAtURL:toDirectoryAtURL:restoreAttributes:progressBlock:error:)
    func extractTar(at tarURL: URL, to dirURL: URL, restoreAttributes: Bool = true, progressBody: ((Double) -> Void)? = nil) throws {
        try KBTarUnarchiver(tarURL: tarURL, options: restoreAttributes ? .restoresFileAttributes : []).extract(to: dirURL, progressBody: progressBody)
    }
    
    /// Creates a Tar file at `tarURL`.
    /// - Parameter at: The path at which the Tar file should be created.
    /// - Parameter from: A directory containing the files that that should be archived.
    /// - Parameter supportsAliasFiles: The Tar format doesn't support alias files by default, only symbolic links. If this
    ///     is set to `true`, archiving will check for alias files and store them as symbolic links. This can take longer.
    /// - Parameter progressBody: A closure with a `Double` parameter representing the current progress (from 0.0 to 1.0).
    @objc(createTarAtURL:fromDirectoryAtURL:supportsAliasFiles:progressBlock:error:)
    func createTar(at tarURL: URL, from dirURL: URL, supportsAliasFiles: Bool = true, progressBody: ((Double) -> Void)? = nil) throws {
        try KBTarArchiver(directoryURL: dirURL, options: supportsAliasFiles ? .supportsAliasFiles : []).archive(to: tarURL, progressBody: progressBody)
    }
}
