//
//  Item.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
