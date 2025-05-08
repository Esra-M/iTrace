//
//  ContentView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 19.04.25.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            VStack {
                Text("Welcome to Usability Testing")
                    .font(.largeTitle)
                    .bold()
                    .padding()
                
                Text("In this application you will compare different interaction methods for the Apple Vision Pro")
                    .font(.headline)
                    .padding(.bottom, 100)
                    
                HStack(spacing: 100) {
                    VStack{
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 50))
                        Text("Keyboard & Mouse")
                    }
                    VStack{
                        Image(systemName: "eye")
                            .font(.system(size: 50))
                        Text("Gaze")
                    }
                    VStack{
                        Image(systemName: "hourglass.badge.eye")
                            .font(.system(size: 50))
                        Text("Dwell")
                    }
                    VStack{
                        Image(systemName: "brain.filled.head.profile")
                            .font(.system(size: 50))
                        Text("Head")
                    }
                    VStack{
                        Image(systemName: "hand.palm.facing")
                            .font(.system(size: 50))
                        Text("Wrist")
                    }
                    VStack{
                        Image(systemName: "hand.point.up.left")
                            .font(.system(size: 50))
                        Text("Index Finger")
                    }
                }
                .padding(.bottom, 100)
                .font(.title3)
                
                Button("Start") {
                    
                    appState.currentPage = .keyboard
                }
                .font(.title)

            }
        }
    }
}
