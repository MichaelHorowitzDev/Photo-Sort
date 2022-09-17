//
//  Rearrange.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 6/27/22.
//

import Photos

private func getImageDate(url: URL) -> Date? {
  let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)!
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

private func getFiles(url: URL) -> FileManager.DirectoryEnumerator? {
  FileManager.default.enumerator(atPath: url.path)
}

private var processedDates = [String: Int]()

private func arrangeImage(file: URL, outputDir: URL, options: ImageSortOptions) throws {
  if !["jpeg", "jpeg"].contains(file.pathExtension) {
    return
  }

  guard let imageDate = getImageDate(url: file) else { return }

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

    var outputURL = outputURL
    while outputURL != outputDir {
      try FileManager.default.setAttributes(attributes, ofItemAtPath: outputURL.path)
      outputURL.deleteLastPathComponent()
    }

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
}

enum SortError: String, Error {
  case directoryDoesntExist = "Directory Doesn't Exist"
}

func sortImages(inputDir: URL, outputDir: URL, options: ImageSortOptions, currentProgress: (Progress) -> Void) throws {
  if let enumerator = getFiles(url: inputDir) {
    let allFiles = enumerator.allObjects.compactMap { $0 as? String }
    let count = allFiles.count
    let progress = Progress(totalUnitCount: Int64(count))
    for (index, file) in allFiles.enumerated() {
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
