//
//  Rearrange.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 6/27/22.
//

import Photos
import EXIF

private func getImageDate(url: URL) -> Date? {
  ImageMetadata(imageURL: url)?.exif?.dateTimeOriginal
}

private func getVideoDate(url: URL) -> Date? {
  let asset = AVAsset(url: url)
  let metadata = asset.metadata

  return metadata.first(where: { $0.commonKey == .commonKeyCreationDate })?.dateValue
}

private func getTiffDate(url: URL) -> Date? {
  let metadata = ImageMetadata(imageURL: url)

  let tiffDate = metadata?.tiff?.dateTime
  let exifDate = metadata?.exif?.dateTimeOriginal
  let fileCreationDate = (try? FileManager.default.attributesOfItem(atPath: url.path) as [FileAttributeKey: Any])?[.creationDate] as? Date

  return tiffDate ?? exifDate ?? fileCreationDate
}

private func getFiles(url: URL) -> FileManager.DirectoryEnumerator? {
  FileManager.default.enumerator(atPath: url.path)
}

struct DuplicateFile: Hashable {
  let source: URL
  let destination: URL
}

func isVideoFileExtension(_ fileExtension: String) -> Bool {
    let videoExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "flv", "wmv", "webm", "mpeg", "mpg", "m4v", "3gp", "3g2", "m2ts"]
    return videoExtensions.contains(fileExtension.lowercased())
}

func isExifImageFileExtension(_ fileExtension: String) -> Bool {
    let exifImageExtensions: Set<String> = ["jpg", "jpeg", "tiff", "tif", "heif", "heic", "dng", "raw"]
    return exifImageExtensions.contains(fileExtension.lowercased())
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
  case noFilesFound = "No Photos or Videos Found"

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

actor ImageSorter {
  private var processedDates = [String: Int]()
  private var duplicateFiles = Set<DuplicateFile>()
  private var destinationFileMap = [URL: URL]()

  private var progress = Progress()

  @MainActor private let currentProgress: @Sendable (Progress) -> Void
  private let handleDuplicates: (ImageSorter) -> Void
  private let handleError: (Error) -> Void

  private let inputDir: URL
  private let outputDir: URL

  private var canUpdateProgress = true

  private let options: ImageSortOptions

  init(
    inputDir: URL,
    outputDir: URL,
    options: ImageSortOptions,
    currentProgress: @Sendable @escaping (Progress) -> Void,
    handleDuplicates: @escaping (ImageSorter) -> Void,
    handleError: @escaping (Error) -> Void
  ) {
    self.inputDir = inputDir
    self.outputDir = outputDir
    self.options = options
    self.currentProgress = currentProgress
    self.handleDuplicates = handleDuplicates
    self.handleError = handleError
  }

  func reportError(_ error: Error) async {
    self.processedDates.removeAll()
    self.duplicateFiles.removeAll()
    self.destinationFileMap.removeAll()

    handleError(error)
    canUpdateProgress = false
  }

  func updateProgress(_ progress: Progress) async {
    if canUpdateProgress {
      currentProgress(progress)
    }
  }

  func sortImages() async {
    processedDates.removeAll()
    duplicateFiles.removeAll()
    destinationFileMap.removeAll()
    if let enumerator = getFiles(url: inputDir) {
      let allFiles = enumerator.allObjects
        .compactMap { $0 as? String }
        .filter { str in
          let file = inputDir.appendingPathComponent(str)

          let isPhoto = isExifImageFileExtension(file.pathExtension)
          let isVideo = isVideoFileExtension(file.pathExtension)

          return options.typesToSort == .photos && isPhoto || options.typesToSort == .videos && isVideo || options.typesToSort == .both && (isPhoto || isVideo)
        }
      let count = allFiles.count

      self.progress = Progress(totalUnitCount: Int64(count))

      await updateProgress(progress)

      for file in allFiles {
        if progress.isCancelled {
          await reportError(SortError.operationCancelled)
          return
        }
        let fileURL = inputDir.appendingPathComponent(file)
        do {
          let result = try arrangeImage(file: fileURL, outputDir: outputDir, options: options)
          if result {
            progress.completedUnitCount = progress.completedUnitCount + 1
            await updateProgress(progress)
          }
        } catch {
          await reportError(error)
          return
        }
      }

      if !duplicateFiles.isEmpty {
        self.handleDuplicates(self)
      }

    } else {
      await reportError(SortError.directoryDoesntExist)
      return
    }
  }

  func handleDuplicates(dupeFileOption: DupeFileOption) async {
    for duplicateFile in duplicateFiles {
      await handleDuplicate(duplicateFile: duplicateFile, dupeFileOption: dupeFileOption)
    }
  }

  struct DupeFileOptions {
    let option: DupeFileOption
    let applyToAll: Bool
  }

  func getDuplicate() -> DuplicateFile? {
    duplicateFiles.randomElement()
  }

  func getDuplicateCount() -> Int {
    duplicateFiles.count
  }

  func handleDuplicate(duplicateFile: DuplicateFile, dupeFileOption: DupeFileOption) async {
    let (file, destination) = (duplicateFile.source, duplicateFile.destination)

    switch dupeFileOption {
    case .keepBoth:
      await keepBoth()
    case .skip:
      break
    case .replace:
      do {
        try await destination.moveToTrash()
        if options.copy {
          try FileManager.default.copyItem(at: file, to: destination)
        } else {
          try FileManager.default.moveItem(at: file, to: destination)
        }

      } catch {
        await reportError(error)
        return
      }
    }

    duplicateFiles.remove(duplicateFile)

    progress.completedUnitCount = progress.completedUnitCount + 1

    await updateProgress(progress)

    func keepBoth() async {
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
          await reportError(error)
          return
        }
      }
    }
  }

  private func arrangeImage(file: URL, outputDir: URL, options: ImageSortOptions) throws -> Bool {
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
}
