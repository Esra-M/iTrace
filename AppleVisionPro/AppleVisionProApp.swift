//
//  AppleVisionProApp.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 19.04.25.
//

import SwiftUI


@main
struct AppleVisionProApp: App {

    var body: some Scene {
        WindowGroup() {
            ContentView()
        }
        
        ImmersiveSpace(id: "Volume"){
            SelectionView()
        }
        
        .windowResizability(.contentSize)
    }
}
