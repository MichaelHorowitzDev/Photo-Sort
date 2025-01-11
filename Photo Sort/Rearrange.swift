//
//  Rearrange.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 6/27/22.
//

import Photos
import EXIF

private func getImageDate(url: URL) -> Date? {
  guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
  if let dict = imageProperties as? [String: Any],
     let exif = dict["{Exif}"] as? [String: Any],
     let dateString = exif["DateTimeOriginal"] as? String,
     let date = dateFormatter.date(from: dateString) {
    return date
  } else {
    return nil
  }
}

private func getVideoDate(url: URL) -> Date? {
  let asset = AVAsset(url: url)
  let metadata = asset.metadata

  return metadata.first(where: { $0.commonKey == .commonKeyCreationDate })?.dateValue
}

private func getTiffDate(url: URL) -> Date? {
  let metadata = ImageMetadata(imageURL: url)

  if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) as [FileAttributeKey: Any],
      let creationDate = attributes[FileAttributeKey.creationDate] as? Date {
      print(creationDate)
      }

  return metadata?.tiff?.dateTime ?? metadata?.exif?.dateTime ?? (try? FileManager.default.attributesOfItem(atPath: url.path) as [FileAttributeKey: Any])?[FileAttributeKey.creationDate] as? Date
}

private func getFiles(url: URL) -> FileManager.DirectoryEnumerator? {
  FileManager.default.enumerator(atPath: url.path)
}

private var processedDates = [String: Int]()

struct DuplicateFile: Hashable {
  let source: URL
  let destination: URL
}

private var duplicateFiles = Set<DuplicateFile>()

private var destinationFileMap = [URL: URL]()

func isVideoFileExtension(_ fileExtension: String) -> Bool {
    let videoExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "flv", "wmv", "webm", "mpeg", "mpg", "m4v", "3gp", "3g2", "m2ts"]
    return videoExtensions.contains(fileExtension.lowercased())
}

func isExifImageFileExtension(_ fileExtension: String) -> Bool {
    let exifImageExtensions: Set<String> = ["jpg", "jpeg", "tiff", "tif", "heif", "heic", "dng", "raw"]
    return exifImageExtensions.contains(fileExtension.lowercased())
}

private func arrangeImage(file: URL, outputDir: URL, options: ImageSortOptions) throws -> Bool {
  print(file.pathExtension)
  if options.typesToSort == .videos && isExifImageFileExtension(file.pathExtension) || options.typesToSort == .photos && isVideoFileExtension(file.pathExtension) {
    return true
  }
  guard let imageDate = if file.pathExtension == "tiff" {
    getTiffDate(url: file)
  } else if isVideoFileExtension(file.pathExtension) {
    getVideoDate(url: file)
  } else {
    getImageDate(url: file)
  } else { return true }

  let pathTypes = [
    options.year ? String(imageDate.year) : "",
    options.month ? imageDate.month(from: options.monthFormat) : "",
    options.day ? String(imageDate.day) : ""
  ].filter { !$0.isEmpty }

  let outputURL = pathTypes.reduce(outputDir) { url, component in
    url.appendingPathComponent(component)
  }

  let originalDestinationURL: URL
  originalDestinationURL = outputURL.appendingPathComponent(file.lastPathComponent)

  if let url = destinationFileMap[originalDestinationURL] {
    duplicateFiles.insert(DuplicateFile(source: file, destination: url))
    return false
  }

  let url: URL
  if options.renamePhotosToExif {
    let date = imageDate.formatted(format: options.renamePhotosFormat)
    processedDates[date, default: 0] += 1
    let number = processedDates[date]!
    let formattedNumber = NumberFormatterValue(number)
      .minimumIntegerDigits(3)
      .string()!
    var path = date + "_\(formattedNumber)"
    if !file.pathExtension.isEmpty {
      path.append("." + file.pathExtension)
    }
    url = outputURL.appendingPathComponent(path)
  } else {
    url = outputURL.appendingPathComponent(file.lastPathComponent)
  }

  destinationFileMap[originalDestinationURL] = url

  do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    if options.copy {
      try FileManager.default.copyItem(at: file, to: url)
    } else {
      try FileManager.default.moveItem(at: file, to: url)
    }
    let attributes: [FileAttributeKey: Any] = [
      .creationDate: options.creationDateExif ? imageDate : Date(),
      .modificationDate: options.modificationDateExif ? imageDate : Date()
    ]
    try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)

  } catch CocoaError.fileWriteFileExists {
    duplicateFiles.insert(DuplicateFile(source: file, destination: url))
    return false
  } catch {
    throw error
  }
  return true
}

enum MonthFormat: String, CaseIterable {
  case numeric = "Numeric: \"1\""
  case numericPadding = "Numeric with Padding: \"01\""
  case shorthand = "Shorthand: \"Jan\""
  case fullName = "Full Name: \"January\""
  case narrowName = "Narrow Name: \"J\""

  var dateFormat: String {
    switch self {
    case .numeric:
      return "M"
    case .numericPadding:
      return "MM"
    case .shorthand:
      return "MMM"
    case .fullName:
      return "MMMM"
    case .narrowName:
      return "MMMMM"
    }
  }
}

struct ImageSortOptions {
  let year: Bool
  let month: Bool
  let monthFormat: MonthFormat
  let week: Bool
  let day: Bool
  let copy: Bool
  let creationDateExif: Bool
  let modificationDateExif: Bool
  let renamePhotosToExif: Bool
  let renamePhotosFormat: String
  let typesToSort: TypesToSort
}

enum SortError: String, LocalizedError {
  case directoryDoesntExist = "Directory Doesn't Exist"
  case operationCancelled = "Operation Cancelled"

  var errorDescription: String? {
    rawValue
  }
}

struct DupeFileOptions {
  let option: DupeFileOption
  let applyToAll: Bool
}

enum DupeFileOption: String, CaseIterable {
  case keepBoth = "Keep Both"
  case skip = "Skip"
  case replace = "Replace"
}

func handleDuplicate(
  duplicateFile: DuplicateFile,
  options: ImageSortOptions,
  initialProgress: Progress,
  currentProgress: (Progress) -> Void,
  dupeFileOption: DupeFileOption
) throws {
  let progress = initialProgress

  let (file, destination) = (duplicateFile.source, duplicateFile.destination)

  switch dupeFileOption {
  case .keepBoth:
    try keepBoth()
  case .skip:
    break
  case .replace:
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      do {
        try await destination.moveToTrash()
        if options.copy {
          try FileManager.default.copyItem(at: file, to: destination)
        } else {
          try FileManager.default.moveItem(at: file, to: destination)
        }

        semaphore.signal()
      } catch {
        throw error
      }
    }
    semaphore.wait()
  }

  duplicateFiles.remove(duplicateFile)

  progress.completedUnitCount = progress.completedUnitCount + 1

  currentProgress(progress)

  func keepBoth() throws {
    guard let imageDate = if file.pathExtension == "tiff" {
      getTiffDate(url: file)
    } else if isVideoFileExtension(file.pathExtension) {
      getVideoDate(url: file)
    } else {
      getImageDate(url: file)
    } else { return }

    var n = 1
    while true {
      let destination = destination.appendingToFileName(" (\(n))")
      do {
        if options.copy {
          try FileManager.default.copyItem(at: file, to: destination)
        } else {
          try FileManager.default.moveItem(at: file, to: destination)
        }
        let attributes: [FileAttributeKey: Any] = [
          .creationDate: options.creationDateExif ? imageDate : Date(),
          .modificationDate: options.modificationDateExif ? imageDate : Date()
        ]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: destination.path)

        break

      } catch CocoaError.fileWriteFileExists {
        n += 1
        continue
      } catch {
        throw error
      }
    }
  }
}

private func handleDuplicates(duplicate: ((DuplicateFile, Bool) -> Bool)) {
  if duplicateFiles.isEmpty {
    return
  }

  print(duplicateFiles.count)

  let result = duplicate(duplicateFiles.randomElement()!, duplicateFiles.count > 1)

  if result {
    handleDuplicates(duplicate: duplicate)
  }
}

func handleDuplicates(
  options: ImageSortOptions,
  initialProgress: Progress,
  currentProgress: (Progress) -> Void,
  dupeFileOption: DupeFileOption
) throws {
  for duplicateFile in duplicateFiles {
    try handleDuplicate(duplicateFile: duplicateFile, options: options, initialProgress: initialProgress, currentProgress: currentProgress, dupeFileOption: dupeFileOption)
  }
}

func sortImages(
  inputDir: URL,
  outputDir: URL,
  options: ImageSortOptions,
  currentProgress: (Progress) -> Void,
  duplicates: (Set<DuplicateFile>) -> Void
) throws {
  processedDates.removeAll()
  duplicateFiles.removeAll()
  destinationFileMap.removeAll()
  if let enumerator = getFiles(url: inputDir) {
    let allFiles = enumerator.allObjects
      .compactMap { $0 as? String }
      .filter { str in
        let file = inputDir.appendingPathComponent(str)

        print(file.pathExtension)

        let isPhoto = isExifImageFileExtension(file.pathExtension)
        let isVideo = isVideoFileExtension(file.pathExtension)

        return options.typesToSort == .photos && isPhoto || options.typesToSort == .videos && isVideo || options.typesToSort == .both && (isPhoto || isVideo)
      }
    let count = allFiles.count
    let progress = Progress(totalUnitCount: Int64(count))

    currentProgress(progress)

    print("initial progress", progress)
    var isCancelled = false
    progress.cancellationHandler = {
      isCancelled = true
    }
    for file in allFiles {
      if isCancelled {
        throw SortError.operationCancelled
      }
      let fileURL = inputDir.appendingPathComponent(file)
      do {
        let result = try arrangeImage(file: fileURL, outputDir: outputDir, options: options)
        print(progress.completedUnitCount)
        if result {
          print(fileURL)
          progress.completedUnitCount = progress.completedUnitCount + 1
          currentProgress(progress)
        }
      } catch {
        throw error
      }
    }

    if !duplicateFiles.isEmpty {
      duplicates(duplicateFiles)
    }

  } else {
    throw SortError.directoryDoesntExist
  }
}
