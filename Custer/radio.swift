//
//  radio.swift
//  Custer
//
//  Created by Serhiy Mytrovtsiy on 07/06/2020.
//  Modified by Diego Rainero on 18/01/2022.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2022 Diego Rainero. All rights reserved.
//

import Foundation
import os.log

class Radio: NSObject {
  public static let shared = Radio()
  
  struct Radio {
    var name: String = ""
    var url: String = ""
    var favicon: String = ""
    var countrycode: String = "IT"
    
  }
  
  
  override init() {
    super.init()
    _ = self.getLatestRadios()
  }
  //private let radiosURL = "http://all.api.radio-browser.info/json/stations"
  private let radiosURL = "https://de1.api.radio-browser.info/json/stations/search?limit=10&name=rmc%20voy&hidebroken=true&order=clickcount&reverse=true"
  private var radios = [Radio]()
  
  private func getLatestRadios() -> String {
    guard let url = URL(string: radiosURL) else {
      return "error"
    }
    let semaphore = DispatchSemaphore(value: 0)
    let result = ""
    
    let session = URLSession.shared
    session.dataTask(with: url) { (data, response, error) in
      if let response = response {
        print(response)
      }
      
      if let data = data {
        print(data)
        do {
          let json = self.parseJsonData(data: data)
          semaphore.signal()
          print(json)
        }
        
      }
    }.resume()
    semaphore.wait()
    return result
  }
  
  func parseJsonData(data: Data) -> [Radio] {
    
    var radios = [Radio]()
    
    do {
      let jsonResult = try JSONSerialization.jsonObject(with: data, options: [])
      // Parse JSON data
      
      let jsonRadios = jsonResult as! [AnyObject]
      for jsonRadio in jsonRadios {
        var radio = Radio()
        radio.name = jsonRadio["name"] as! String
        radio.url = jsonRadio["url"] as! String
        radios.append(radio)
      }
      
    } catch {
      print(error)
    }
    
    return radios
  }
}
