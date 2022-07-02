//
//  Date+Extensions.swift
//  Photo Sort
//
//  Created by Michael Horowitz on 6/27/22.
//

import Foundation

extension Date {
  var year: Int {
    Calendar.current.component(.year, from: self)
  }
  var month: Int {
    Calendar.current.component(.month, from: self)
  }
  var day: Int {
    Calendar.current.component(.day, from: self)
  }
}
