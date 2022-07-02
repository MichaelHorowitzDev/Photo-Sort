//
//  ContentView.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 5/10/22.
//

import SwiftUI

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
  @Published var year = true
  @Published var month = true
  @Published var copyPhotos = true
  @Published var filesOpen = false
  
  func openFolderPath(result: @escaping (URL?) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.toolbarStyle = .expanded
    self.filesOpen = true
    panel.begin { response in
      if response == .OK {
        result(panel.url)
      } else {
        result(nil)
      }
      self.filesOpen = false
    }
  }
  
  func setInputDir() {
    openFolderPath { url in
      if let url = url {
        self.inputDir = url.path
      }
    }
  }
  
  func setOutputDir() {
    openFolderPath { url in
      if let url = url {
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
  @State private var alertResult: AlertResult?
    var body: some View {
      VStack {
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
          Toggle("Sort into months", isOn: $viewModel.month)
          Toggle("Copy Photos", isOn: $viewModel.copyPhotos)
        }
        .padding()
        Button {
          let input = URL(fileURLWithPath: viewModel.inputDir)
          let output = URL(fileURLWithPath: viewModel.outputDir)
          do {
            try sortImages(
              inputDir: input,
              outputDir: output,
              options: ImageSortOptions(
                year: viewModel.year,
                month: viewModel.month,
                week: false,
                day: false,
                copy: viewModel.copyPhotos)
              )
            self.alertResult = AlertResult(result: "Success Sorting Photos")
          } catch {
            self.alertResult = AlertResult(error: error)
          }
        } label: {
          Text("Sort Photos")
        }
        .disabled(viewModel.inputDir.isEmpty || viewModel.outputDir.isEmpty)
        .alert(item: $alertResult) { alertResult in
          Alert(title: Text(alertResult.error ? "Error" : "Success"), message: Text(alertResult.result), dismissButton: .default(Text("OK")))
        }
      }
      .disabled(viewModel.filesOpen)
      .frame(minWidth: 600, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
