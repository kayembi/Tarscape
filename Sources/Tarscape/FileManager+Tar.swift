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
    func extractTar(at tarURL: URL, to dirURL: URL, options: KBTarUnarchiver.Options = [.restoreFileAttributes], progress: Progress? = nil) throws {
        let unarchiver = try KBTarUnarchiver(tarURL: tarURL, options: options)
        
        var progressBody: ((Double, Int64) -> Void)?
        
        if progress != nil {
            // Asking for the progress count enumerates through files in advance, so only
            // do this if we actually want to use the progress.
            progress?.totalUnitCount = unarchiver.progressCount
            progressBody = {(_, currentFileNum) in
                progress?.completedUnitCount = currentFileNum
            }
        }
        
        try KBTarUnarchiver(tarURL: tarURL, options: options).extract(to: dirURL, progressBody: progressBody)
    }
    
    @nonobjc
    func createTar(at tarURL: URL, from dirURL: URL, filter: KBURLFilter? = nil, options: KBTarArchiver.Options = [],  progress: Progress? = nil) throws {
        let archiver = KBTarArchiver(directoryURL: dirURL, options: options)
        
        var progressBody: ((Double, Int64) -> Void)?
        
        if progress != nil {
            progress?.totalUnitCount = archiver.progressCount
            progressBody = {(_, currentFileNum) in
                progress?.completedUnitCount = currentFileNum
            }
        }
        
        try KBTarArchiver(directoryURL: dirURL, filter: filter, options: options).archive(to: tarURL, progressBody: progressBody)
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
    func extractTar(at tarURL: URL, to dirURL: URL, restoreAttributes: Bool,  progress: Progress? = nil) throws {
        try extractTar(at: tarURL, to: dirURL, options: restoreAttributes ? .restoreFileAttributes : [], progress: progress)
    }
    
    /// Creates a Tar file at `tarURL`.
    /// - Parameter at: The path at which the Tar file should be created.
    /// - Parameter from: A directory containing the files that that should be archived.
    /// - Parameter convertAliasFiles: The Tar format doesn't support alias files by default, only symbolic links. If this
    ///     is set to `true`, archiving will check for alias files and store them as symbolic links. This can take longer.
    /// - Parameter progressBody: A closure with a `Double` parameter representing the current progress (from 0.0 to 1.0).
    @objc(createTarAtURL:fromDirectoryAtURL:convertAliasFiles:progressBlock:error:)
    func createTar(at tarURL: URL, from dirURL: URL, convertAliasFiles: Bool,  progress: Progress? = nil) throws {
        try createTar(at: tarURL, from: dirURL, options: convertAliasFiles ? .convertAliasFiles : [], progress: progress)
    }
}
