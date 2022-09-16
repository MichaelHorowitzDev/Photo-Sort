//
//  NumberFormatter.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 9/16/22.
//

import Foundation

struct NumberFormatterValue {
  private var formatter = NumberFormatter()
  let number: NSNumber

  init(_ value: Int) {
    self.number = value as NSNumber
  }

  init(_ value: Double) {
    self.number = value as NSNumber
  }
  func string() -> String? {
    let numberFormatter = NumberFormatter()
    numberFormatter.minimumIntegerDigits = minimumIntegerDigits
    return nil
  }
  private var minimumIntegerDigits: Int = 0
}

extension NumberFormatterValue {
  func minimumIntegerDigits(_ value: Int) -> Self {
    var copy = self
    copy.minimumIntegerDigits = value
    return copy
  }
}
