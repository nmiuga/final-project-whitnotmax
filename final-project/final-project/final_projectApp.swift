//
//  final_projectApp.swift
//  final-project
//
//  Created by Whitman Stewart on 4/13/26.
//

import SwiftUI

@main
struct final_projectApp: App {
    @StateObject private var locationStore = LocationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationStore)
        }
    }
}
