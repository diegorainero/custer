//
//  radio.swift
//  DRadio
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

class Radio {
    public static let shared = Radio()
    
struct Radio {
    var name: String = ""
    var url: String = ""
    var favicon: String = ""
    var countrycode: String = "IT"
 
}

//private let radiosURL = "http://all.api.radio-browser.info/json/stations"
private let radiosURL = "https://de1.api.radio-browser.info/json/stations/search?limit=10&name=rmc%20voy&hidebroken=true&order=clickcount&reverse=true"
private var radios = [Radio]()

func getLatestRadios() {
    guard let radioUrl = URL(string: radiosURL) else {
        return
    }
 
    let request = URLRequest(url: radioUrl)
    let task = URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) -> Void in
 
        if let error = error {
            print(error)
            return
        }
 
        // Parse JSON data
        if let data = data {
            self.radios = self.parseJsonData(data: data)
        }
    })
    os_log("TASK ",task)
    task.resume()
}
 
func parseJsonData(data: Data) -> [Radio] {
 
    var radios = [Radio]()
 
    do {
        let jsonResult = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) as? NSDictionary
 
        // Parse JSON data
        let jsonRadios = jsonResult?["loans"] as! [AnyObject]
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
