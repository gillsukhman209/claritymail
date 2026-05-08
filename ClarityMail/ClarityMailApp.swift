//
//  ClarityMailApp.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

@main
struct ClarityMailApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appearancePreference()
                .fontPreference()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 860)
        .restorationBehavior(.disabled)
        #endif
    }
}
