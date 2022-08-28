//
//  Rearrange.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 6/27/22.
//

import Photos

private func getImageDate(url: URL) -> Date? {
  print("get image date url", url)
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

private func arrangeImage(file: URL, outputDir: URL, options: ImageSortOptions) throws {
  if !["jpeg", "jpeg"].contains(file.pathExtension) {
    return
  }

  let imageDate = getImageDate(url: file)
  guard let imageDate = imageDate else { return }

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
    let url = outputURL.appendingPathComponent(file.lastPathComponent)
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
    print("error moving file")
    print(error)
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
}

enum SortError: String, Error {
  case directoryDoesntExist = "Directory Doesn't Exist"
}

func sortImages(inputDir: URL, outputDir: URL, options: ImageSortOptions) throws {
  if let enumerator = getFiles(url: inputDir) {
    while let file = enumerator.nextObject() as? String {
      let fileURL = inputDir.appendingPathComponent(file)
      do {
        try arrangeImage(file: fileURL, outputDir: outputDir, options: options)
      } catch {
        throw error
      }
    }
  } else {
    throw SortError.directoryDoesntExist
  }
}
