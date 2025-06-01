//
//  TestView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 20.04.25.
//

import SwiftUI

struct TestView: View {

    @EnvironmentObject private var appState: AppState

    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var isLoadingEyeTracking = false

    var body: some View {
        VStack {
            Text("Select a test")
                .padding(.bottom, 100)
                .font(.largeTitle)
                .bold()

            HStack(spacing: 50){
//                VStack{
//                    Image(systemName: "character.cursor.ibeam")
//                        .font(.system(size: 50))
//                        .padding()
//
//                    Button("Typing") {
//                        appState.currentPage = .type
//                    }
//
//                }
//                .frame(height: 150, alignment: .bottom)
                
                
//                VStack{
//                    Image(systemName: "point.topleft.down.to.point.bottomright.filled.curvepath")
//                        .font(.system(size: 50))
//                        .padding()
//
//                    Button("Drag") {
//                        appState.currentPage = .reach
//                        Task {
//                            await openImmersiveSpace(id: "reachObject")
//                        }
//                    }
//
//                }
//                .frame(height: 150, alignment: .bottom)

//                VStack{
//                    Image(systemName: "dot.scope")
//                        .font(.system(size: 50))
//                        .padding()
//
//                    Button("Target") {
//                        appState.currentPage = .select
//                        Task {
//                            await openImmersiveSpace(id: "selectionObject")
//                        }
//                    }
//
//                }
//                .frame(height: 150, alignment: .bottom)
                
                
                VStack{
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 50))
                        .padding()
                    
                    Button("Clicling") {
                        appState.currentPage = .click
                    }

                }
                .frame(height: 150, alignment: .bottom)
                
               VStack{
                   Image(systemName: "scope")
                       .font(.system(size: 45))
                       .padding()
                   
                   Button("Percision") {
                       appState.currentPage = .bullseyeTest
                   }
               }
               .frame(height: 150, alignment: .bottom)
                
                VStack {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 50))
                        .padding()

                    Button(isLoadingEyeTracking ? "Loading..." : "Eye Tracking") {
                        isLoadingEyeTracking = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            appState.currentPage = .eyeTracking
                        }
                    }
                    .disabled(isLoadingEyeTracking)
                }
                .frame(height: 150, alignment: .bottom)
                
                VStack{
                    Image(systemName: "aqi.medium")
                        .font(.system(size: 45))
                        .padding()
                    
                    Button("Spacial Tracking") {
                        Task{
                            await openImmersiveSpace(id: "immersiveTracking")
                            dismissWindow(id: "main")
                        }
                    }
                }
                .frame(height: 150, alignment: .bottom)

            }
        }
    }
}
