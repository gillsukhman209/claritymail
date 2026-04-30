//
//  ClarityMailApp.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

@main
struct ClarityMailApp: App {
    init() {
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
