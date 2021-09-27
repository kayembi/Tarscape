# Tarscape


## About

Tarscape is a Swift package for reading and writing Tar archives on macOS and iOS.


## Installation

Search for `https://github.com/kayembi/Tarscape.git` in Xcode's package manager. Alternatively, download and drag the Tarscape package folder to your Xcode project.

Remember to add `import Tarscape` at the top of Swift files that use Tarscape.


## Usage

### Basic Usage

The simplest way of creating and extracting Tar archives is by using the FileManager extension.

To create a Tar archive:

```swift
// let folderURL = <folder from which to create archive>
// let tarURL = <location at which to create Tar file>
try FileManager.default.createTar(at: tarURL, from: folderURL)
```

To extract a Tar archive:

```swift
// let tarURL = <location of the Tar file>
// let dirURL = <location at which the extracted directory should be created>
try FileManager.default.extractTar(at: tarURL, to: dirURL)
```

The FileManager methods can also be called from Objective-C code.

### Customising Options

You can increase or decrease archiving and extraction times by using `KBTarArchiver` and `KBTarUnarchiver` and changing certain options.

For example, setting `.convertAliasFiles` ensures alias files get stored in the archive correctly, but will slow down the archiving process.

```swift
// If the folder contains or might contain aliases, we should tell 
// the archiver to convert them to symbolic links.
let tarArchiver = KBTarArchiver(directoryURL: dirURL, options: .convertAliasFiles)
try tarArchiver.archive(to: tarURL) { (progressFraction, progressCount) in
    // Update progress here.
}
```

You can also set some options to speed up unarchiving:

```swift
// 1. File attributes such as permissions and modification dates 
//    have to be set using FileManager's setAttributes(_:ofItemAtPath:) 
//    and this is *slow*. If you don't care about such attributes being 
//    restored and can live with default attributes being applied to 
//    extracted files, telling the unarchiver not to restore file attributes
//    can significantly improve extraction speeds. Do this by setting the
//    options parameter and *not* including .restoreFileAttributes.
// 2. Constructing file URLs can be done much faster if we don't have to 
//    worry about special characters and spaces etc that have to be escaped.
//    If you know that most subpaths in the archive don't use special characters
//    or spaces, you can speed up unarchiving by telling the unarchiver as much.
//    Only set this flag if you're sure, though - unarchiving can be slower if
//    you set this flag but it turns out that a lot of subpaths contain spaces
//    or special characters.
let tarUnarchiver = try KBTarUnarchiver(tarURL: tarURL, options: [.mostSubpathsCanBeUnescaped])
try tarUnarchiver.extract(to: dirURL) { (progressFraction, progressCount) in
    // Update progress here.
}

```

### Accessing Individual Archive Entries

If you don't want to extract the entire Tar file but just find a certain file or files within it, you can query it using `KBTarEntry`.

Example:

```swift
let tarUnarchiver = try KBTarUnarchiver(tarURL: tarURL)

// Get a single file:
let fileEntry = try tarUnarchiver.entry(atSubpath: "path/to/file.txt")
let data = fileEntry.regularFileContents()

// Get a directory:
let folderEntry = try tarUnarchiver.entry(atSubpath: "path/to/folder")
for childEntry in folderEntry.descendants {
    // ...
}
```

Note that every time you call `entry(atSubpath:)`, Tarscape has to parse through the entire Tar file until it finds the entry. If you need to look for more than one entry, therefore, you should tell the unarchiver to parse the Tar file first to build up a list of entries:

```swift
let tarUnarchiver = try KBTarUnarchiver(tarURL: tarURL)

// Tell the unarchiver to gather a list of entries. By passing in the "lazily" 
// flag, we tell the unarchiver not to load any data into memory but only the 
// list of entries. The data for each entry will not be read into memory until 
// we call regularFileContents() on a specific entry.
try tarUnarchiver.loadAllEntries(lazily: true)

// Enumerate through root entries (note that rootEntries is nil until 
// loadAllEntries() is called):
for entry in tarUnarchiver.rootEntries {
    // do something...
}

// Find an entry using subscript syntax:
let fileEntry = tarUnarchiver["path/to/file.txt"]
// Load the data for the entry - if "lazily" was set to "true", only now does 
// the data get read from the archive:
let data = fileEntry.regularFileContents()

```

### Documentation

All Tarscape methods are documented using Swift documentation comments. Opt-click a method name in Xcode for Quick Help.

### Limitations

Note that because Tarscape focuses on fast Tar creation and extraction, it does not support compression (it reads and writes .tar files, not tar.gz files). To add support for tar.gz, you'll need a third-party compression library such as [DataCompression](https://github.com/mw99/DataCompression).


## Why Tarscape?

We needed a fast way of archiving file packages (i.e. folders) to a single file format for syncing, preferably written in Swift. There exist several great open source Tar projects for Swift and Objective-C (see [References](#References) below). However, none of them quite suited our requirements:

- SWCompression is written in Swift but is designed to work on in-memory data only - it doesn't work directly with a folder of files on disk. Loading files into memory prior to archiving added too much time for our needs.
- Light Untar and Light Swift Untar work well for extracting files but do not support creating Tar archives.
- Tarkit (DCTar) works well but is written in Objective-C and hasn't been updated for several years.
- We needed archiving, especially, to be fast. This required dropping down to using `stat()` instead of using FileManager's `attributesOfItem(atPath:)`, bypassing `String` when generating octals, and several other optimisations. (Suggestions for further optimisation would be greatly appreciated.)


## References

Tarscape builds on and uses code from the following projects:

- [SW Compression](https://github.com/tsolomko/SWCompression) by Timofey Solomko (c) 2021.
- [tarkit/DCTar](https://github.com/daltoniam/tarkit) by Dalton Cherry (c) 2014.
- [Light Untar](https://github.com/mhausherr/Light-Untar-for-iOS/tree/b76f908f0a3b2d96ed5909938ab45a329f58cdf2) by Mathieu Hausherr Octo Technology (c) 2011.



