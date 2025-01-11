//
//  URL+Extensions.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 1/9/25.
//

import Foundation
import Cocoa

extension URL {
  func appendingToFileName(_ string: String) -> URL {
      let directory = self.deletingLastPathComponent()
      let fileName = self.deletingPathExtension().lastPathComponent
      let fileExtension = self.pathExtension

      let newFileName = "\(fileName)\(string)"
      return directory.appendingPathComponent(newFileName).appendingPathExtension(fileExtension)
  }

  /// Moves the file or directory at the URL to the trash (macOS only).
  /// - Throws: An error if the operation fails.
  func moveToTrash() async throws {
    let workspace = NSWorkspace.shared
    try await workspace.recycle([self])
  }
}
