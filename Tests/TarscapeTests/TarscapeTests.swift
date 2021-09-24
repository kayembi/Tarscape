import XCTest
@testable import Tarscape

final class TarscapeTests: XCTestCase {
    
    func testSimpleRoundTrip() throws {
        
        // Create some files, archive them, extract them, and check that what we
        // got out matches what we put in.
        let fm = FileManager.default
        let tempFolder = fm.temporaryDirectory.appendingPathComponent("tarscape_tests")
        try fm.createDirectory(at: tempFolder, withIntermediateDirectories: false, attributes: nil)
        
        let dirURL = tempFolder.appendingPathComponent("archive_folder")
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: false, attributes: nil)
        
        try "Hello world".write(to: dirURL.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        let innerFolder = dirURL.appendingPathComponent("inner_folder")
        try fm.createDirectory(at: innerFolder, withIntermediateDirectories: false, attributes: nil)
        let file2Date = Date(timeIntervalSinceNow: -(3 * 24 * 60 * 60))
        let file2URL = innerFolder.appendingPathComponent("file2.txt")
        try "Another file".write(to: file2URL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: file2Date], ofItemAtPath: file2URL.path)
        try Data().write(to: dirURL.appendingPathComponent("empty_file"))
        
        // Archive the folder.
        let tarURL = tempFolder.appendingPathComponent("archive.tar")
        try fm.createTar(at: tarURL, from: dirURL)
        
        // And unarchive.
        let untarURL = tempFolder.appendingPathComponent("unarchived")
        try fm.extractTar(at: tarURL, to: untarURL)
        
        // Check things match.
        XCTAssert(fm.fileExists(atPath: untarURL.appendingPathComponent("file1.txt").path))
        let f1text = try String(contentsOf: untarURL.appendingPathComponent("file1.txt"), encoding: .utf8)
        XCTAssert(f1text == "Hello world")
        var isDir:ObjCBool = false
        let untarInnerFolder =  untarURL.appendingPathComponent("inner_folder")
        XCTAssert(fm.fileExists(atPath: untarInnerFolder.path, isDirectory: &isDir) && isDir.boolValue)
        let untarFile2URL = untarInnerFolder.appendingPathComponent("file2.txt")
        XCTAssert(fm.fileExists(atPath: untarFile2URL.path))
        let f2text = try String(contentsOf: untarFile2URL, encoding: .utf8)
        XCTAssert(f2text == "Another file")
        XCTAssert(fm.fileExists(atPath: untarURL.appendingPathComponent("empty_file").path))
        
        if let emptyLen = try fm.attributesOfItem(atPath: untarURL.appendingPathComponent("empty_file").path)[.size] as? Int {
            XCTAssert(emptyLen == 0)
        }
        
        // Check dates match.
        let untarFile2Date = try fm.attributesOfItem(atPath: untarFile2URL.path)[.modificationDate] as? Date
        XCTAssert(untarFile2Date != nil)
        
        // Dates should match down to seconds, but not at any finer granularity, so use date components
        // for comparison becuase Date1 == Date2 is likely to fail.
        if let untarFile2Date = untarFile2Date {
            let dateComps1 = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute, .second], from: file2Date)
            let dateComps2 = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute, .second], from: untarFile2Date)
            XCTAssert(dateComps1 == dateComps2)
        }
        
        try fm.removeItem(at: tempFolder)
    }
}
