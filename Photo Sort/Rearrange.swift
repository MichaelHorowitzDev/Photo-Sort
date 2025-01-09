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

func isVideoFileExtension(_ fileExtension: String) -> Bool {
    let videoExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "flv", "wmv", "webm", "mpeg", "mpg", "m4v", "3gp", "3g2", "m2ts"]
    return videoExtensions.contains(fileExtension.lowercased())
}

func isExifImageFileExtension(_ fileExtension: String) -> Bool {
    let exifImageExtensions: Set<String> = ["jpg", "jpeg", "tiff", "tif", "heif", "heic", "dng", "raw"]
    return exifImageExtensions.contains(fileExtension.lowercased())
}

private func arrangeImage(file: URL, outputDir: URL, options: ImageSortOptions) throws {
  print(file.pathExtension)
  if options.typesToSort == .videos && isExifImageFileExtension(file.pathExtension) || options.typesToSort == .photos && isVideoFileExtension(file.pathExtension) {
    return
  }
  guard let imageDate = if file.pathExtension == "tiff" {
    getTiffDate(url: file)
  } else if isVideoFileExtension(file.pathExtension) {
    getVideoDate(url: file)
  } else {
    getImageDate(url: file)
  } else { return }

  let pathTypes = [
    options.year ? String(imageDate.year) : "",
    options.month ? imageDate.month(from: options.monthFormat) : "",
    options.day ? String(imageDate.day) : ""
  ].filter { !$0.isEmpty }

  let outputURL = pathTypes.reduce(outputDir) { url, component in
    url.appendingPathComponent(component)
  }

  do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
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


  } catch {
    throw error
  }
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

func sortImages(inputDir: URL, outputDir: URL, options: ImageSortOptions, currentProgress: (Progress) -> Void) throws {
  processedDates.removeAll()
  if let enumerator = getFiles(url: inputDir) {
    let allFiles = enumerator.allObjects.compactMap { $0 as? String }
    let count = allFiles.count
    let progress = Progress(totalUnitCount: Int64(count))
    var isCancelled = false
    progress.cancellationHandler = {
      isCancelled = true
    }
    for (index, file) in allFiles.enumerated() {
      if isCancelled {
        throw SortError.operationCancelled
      }
      let fileURL = inputDir.appendingPathComponent(file)
      do {
        try arrangeImage(file: fileURL, outputDir: outputDir, options: options)
        progress.completedUnitCount = Int64(index + 1)
        currentProgress(progress)
      } catch {
        throw error
      }
    }
  } else {
    throw SortError.directoryDoesntExist
  }
}
