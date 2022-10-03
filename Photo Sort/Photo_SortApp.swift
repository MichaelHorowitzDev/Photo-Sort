//
//  Photo_SortApp.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 5/10/22.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}

@main
struct PhotoSortApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
