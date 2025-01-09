//
//  ContentView.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 5/10/22.
//

import SwiftUI
import StoreKit

private class ViewModel: ObservableObject {
  @Published var inputDir = "" {
    didSet {
      if sameDir {
        outputDir = inputDir
      }
    }
  }
  @Published var outputDir = ""
  @Published var sameDir = false {
    didSet {
      outputDir = sameDir ? inputDir : ""
    }
  }

  @AppStorage("year") var year = true
  @AppStorage("month") var month = true
  @AppStorage("monthFormat") var monthFormat: MonthFormat = .fullName
  @AppStorage("day") var day = true
  @AppStorage("copyPhotos") var copyPhotos = true
  @AppStorage("creationDateExif") var creationDateExif = true
  @AppStorage("modificationDateExif") var modificationDateExif = true
  @AppStorage("rename") var rename = false
  @AppStorage("renameFormat") var renameFormat = "yyyy-MM-dd"

  @Published var filesOpen = false

  @Published var progress: Progress?
  @Published var alertResult: AlertResult?

  func sortPhotos() {
    let input = URL(fileURLWithPath: self.inputDir)
    let output = URL(fileURLWithPath: self.outputDir)
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let options = ImageSortOptions(
          year: self.year,
          month: self.month,
          monthFormat: self.monthFormat,
          week: false,
          day: self.day,
          copy: self.copyPhotos,
          creationDateExif: self.creationDateExif,
          modificationDateExif: self.modificationDateExif,
          renamePhotosToExif: self.rename,
          renamePhotosFormat: self.renameFormat)

        try sortImages(
          inputDir: input,
          outputDir: output,
          options: options
        ) { progress in
          DispatchQueue.main.async {
            self.progress = progress
          }
        }
        DispatchQueue.main.async {
          self.progress = nil
          self.alertResult = AlertResult(result: "Success Sorting Photos")
        }
      } catch {
        DispatchQueue.main.async {
          self.progress = nil
          self.alertResult = AlertResult(error: error)
        }
      }
    }
  }

  func openFolderPath(result: @escaping (URL?) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.toolbarStyle = .expanded
    self.filesOpen = true
    panel.begin { response in
      self.filesOpen = false
      if response == .OK {
        result(panel.url)
      }
    }
  }

  func setInputDir() {
    openFolderPath { url in
      if let url {
        self.inputDir = url.path
      }
    }
  }

  func setOutputDir() {
    openFolderPath { url in
      if let url {
        self.outputDir = url.path
      }
    }
  }
}

private struct AlertResult: Identifiable {
  let id = UUID()
  let result: String
  let error: Bool

  init(result: String) {
    self.result = result
    self.error = false
  }
  init(error: Error) {
    self.result = error.localizedDescription
    self.error = true
  }
}

struct ContentView: View {
  @ObservedObject private var viewModel = ViewModel()
    var body: some View {
      ZStack {
        Form {
          HStack {
            TextField("Image Folder", text: $viewModel.inputDir)
              .disabled(true)
            Button {
              viewModel.setInputDir()
            } label: {
              Image(systemName: "folder.fill.badge.plus")
            }
            Spacer()
          }
          HStack {
            Group {
              TextField("Output Directory", text: $viewModel.outputDir)
                .disabled(true)
              Button {
                viewModel.setOutputDir()
              } label: {
                Image(systemName: "folder.fill.badge.plus")
              }
              Spacer()
            }
            .disabled(viewModel.sameDir)
            Toggle("Same as input", isOn: $viewModel.sameDir)
          }
          Toggle("Sort into years", isOn: $viewModel.year)
          HStack(spacing: 20) {
            Toggle("Sort into months", isOn: $viewModel.month)
            HStack(spacing: 0) {
              Text("Month Format: ")
              Picker("", selection: $viewModel.monthFormat) {
                ForEach(MonthFormat.allCases, id: \.self) {
                  Text($0.rawValue)
                }
              }
              .fixedSize()
              .labelsHidden()
              .pickerStyle(.menu)
            }
            .disabled(!viewModel.month)
          }
          Group {
            Toggle("Sort into days", isOn: $viewModel.day)
            Toggle("Copy Photos", isOn: $viewModel.copyPhotos)
            Toggle("Creation Date Same as EXIF Date", isOn: $viewModel.creationDateExif)
            Toggle("Modification Date same as EXIF Date", isOn: $viewModel.modificationDateExif)
            HStack(spacing: 20) {
              Toggle("Rename Files", isOn: $viewModel.rename)
              VStack {
                HStack {
                  TextField("", text: $viewModel.renameFormat)
                    .disabled(!viewModel.rename)
                  Link(destination: URL(string: "https://nsdateformatter.com/")!) {
                    Text("􀅴")
                  }
                }
                Text("Format for Current Date:")
                Text(Date().formatted(format: viewModel.renameFormat))
              }
              .fixedSize(horizontal: true, vertical: false)
              .labelsHidden()
            }
          }
          Group {
            if let progress = viewModel.progress {
              Button {
                progress.cancel()
              } label: {
                Text("Cancel")
              }
            } else {
              Button {
                viewModel.sortPhotos()
              } label: {
                Text("Sort Photos")
              }
            }
          }
          .disabled(viewModel.inputDir.isEmpty || viewModel.outputDir.isEmpty)
          .alert(item: $viewModel.alertResult) { alertResult in
            Alert(
              title: Text(alertResult.error ? "Error" : "Success"),
              message: Text(alertResult.result),
              dismissButton: .default(Text("OK"))
            )
          }

          if let progress = viewModel.progress {
            VStack {
              ProgressView(value: progress.fractionCompleted)
              Text("\(progress.completedUnitCount) / \(progress.totalUnitCount)")
            }
          }
        }
        .padding()
        .disabled(viewModel.filesOpen)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        VStack {
          Spacer()
          HStack {
            Button("Rate") {
              if let url = URL(string: "macappstore://itunes.apple.com/app/id\(6443650295)?mt=12&action=write-review") {
                NSWorkspace.shared.open(url)
              }
            }
            .padding()
            Spacer()
            Button("Support") {
              let service = NSSharingService(named: NSSharingService.Name.composeEmail)
              service?.recipients = ["email@michaelhorowitz.dev"]
              service?.subject = "Photo Reorganizer Support"
              let version = ProcessInfo.processInfo.operatingSystemVersionString
              service?.perform(withItems: ["\n\nmacOS \(version)\n\nApp Version 1.1"])
            }
            .padding()
          }
        }
      }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
