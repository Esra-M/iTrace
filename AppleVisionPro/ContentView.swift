//
//  ContentView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 19.04.25.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject private var appState: AppState
    @State private var userName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack {
                Text("Welcome to GazeNav")
                    .font(.largeTitle)
                    .bold()
                
                Text("In this application you can perform eye tracking \n on a video and in your surrounding environment")
                    .font(.title)
                    .padding(50)
                    .multilineTextAlignment(.center)
                
                Text("Before you start, please enter your name:")
                    .font(.title)
                    .padding(.bottom, 10)
                    .padding(.top, 20)
                    .foregroundStyle(.secondary)

                
                TextField("Enter your name", text: $userName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .padding(.bottom, 100)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            appState.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                            appState.currentPage = .test
                        }
                    }
                
                Button(action: {
                    appState.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.currentPage = .test
                }) {
                    Text("Start")
                        .font(.title)
                        .padding()
                }
                .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }
}
