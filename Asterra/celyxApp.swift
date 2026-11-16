//
//  celyxApp.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import SwiftUI

@main
struct celyxApp: App {
    init() {
        // Taps on sky event notifications must reach the app, even from a cold start.
        SkyEventNotifications.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
