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

    var body: some View {
        VStack {
            Text("Select a test")
                .padding(.bottom, 100)
                .font(.largeTitle)
                .bold()

            HStack(spacing: 50){
                VStack{
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 50))
                        .padding()
                    
                    Button("Typing") {
                        appState.currentPage = .type
                    }

                }
                .frame(height: 150, alignment: .bottom)
                
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
                    Image(systemName: "point.topleft.down.to.point.bottomright.filled.curvepath")
                        .font(.system(size: 50))
                        .padding()
                    
                    Button("Drag") {
                        appState.currentPage = .reach
                        Task {
                            await openImmersiveSpace(id: "reachObject")
                        }
                    }

                }
                .frame(height: 150, alignment: .bottom)

                VStack{
                    Image(systemName: "dot.scope")
                        .font(.system(size: 50))
                        .padding()
                    
                    Button("Target") {
                        appState.currentPage = .select
                        Task {
                            await openImmersiveSpace(id: "selectionObject")
                        }
                    }

                }
                .frame(height: 150, alignment: .bottom)
                
                VStack{
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 50))
                        .padding()
                    
                    Button("Eye Tracking") {
                        appState.currentPage = .eyeTracking

                    }

                }
                .frame(height: 150, alignment: .bottom)
            }
        }
    }
}
