//
//  AppleVisionProApp.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 19.04.25.
//

import SwiftUI
import RealityKit
import RealityKitContent


@main
struct AppleVisionProApp: App {
    @StateObject private var appState = AppState()

    var body: some SwiftUI.Scene {
        
        WindowGroup(id: "main") {
            Group {
                switch appState.currentPage {
                case .content:
                    ContentView()
                case .keyboard:
                    KeyboardView()
                case .test:
                    TestView()
                case .type:
                    TypingView()
                case .click:
                    ClickingView()
                case .reach:
                    ReachView()
                case .select:
                    SelectionView()
                case .eyeTracking:
                    EyeTrackingView()
                }
            }
            .environmentObject(appState)
            .animation(.easeInOut, value: appState.currentPage)
        }
        
        ImmersiveSpace(id: "immersiveTracking"){
            ImersiveTrackingView()
        }
        
        
        ImmersiveSpace(id: "selectionObject"){
            SelectionObjectsView()
        }
        
        ImmersiveSpace(id: "reachObject"){
            ReachObjectView()
                .environmentObject(appState)
        }

    }
}

