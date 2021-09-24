//
//  FileManager+Tar.swift
//  FileManager+Tar
//
//  Created by Keith Blount on 20/09/2021.
//

import Foundation

@objc // Expose this extension to Objective-C.
public extension FileManager {
    
    /// Extracts the tar at `tarURL` to `dirURL`.
    /// - Parameter at: The path of the Tar file to extract.
    /// - Parameter to: The path to which to extract the Tar file. A directory will be created at this path containing the extracted files.
    /// - Parameter restoreAttributes: If `false`, file attributes stored in the archive such as modification dates and file
    ///     permissions be ignored. This can significantly speed up the extraction process.
    /// - Parameter progressBody: A closure with a `Double` parameter representing the current progress (from 0.0 to 1.0).
    @objc(extractTarAtURL:toDirectoryAtURL:restoreAttributes:progressBlock:error:)
    func extractTar(at tarURL: URL, to dirURL: URL, restoreAttributes: Bool = true, progressBody: ((Double) -> Void)? = nil) throws {
        let unarchiver = KBTarUnarchiver(tarURL: tarURL)
        unarchiver.restoresFileAttributes = restoreAttributes
        try unarchiver.extract(to: dirURL, progressBody: progressBody)
    }
    
    /// Creates a Tar file at `tarURL`.
    /// - Parameter at: The path at which the Tar file should be created.
    /// - Parameter from: A directory containing the files that that should be archived.
    /// - Parameter progressBody: A closure with a `Double` parameter representing the current progress (from 0.0 to 1.0).
    @objc(createTarAtURL:fromDirectoryAtURL:supportsAliasFiles:progressBlock:error:)
    func createTar(at tarURL: URL, from dirURL: URL, supportsAliasFiles: Bool = true, progressBody: ((Double) -> Void)? = nil) throws {
        try KBTarArchiver(directoryURL: dirURL, supportsAliasFiles: supportsAliasFiles).archive(to: tarURL, progressBody: progressBody)
    }
}
