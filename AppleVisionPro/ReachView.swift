//
//  ReachView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 24.04.25.
//
import SwiftUI

struct ReachView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace


    
    var body: some View {
        ZStack {
            Button(action: {
                appState.reachResult = ""
                appState.currentPage = .test
                Task {
                    await dismissImmersiveSpace()
                }
            }) {
                Image(systemName: "chevron.backward")
                    .padding(20)
            }
            .frame(width: 60, height: 60)
            .offset(x: -580, y: -300)
            
            VStack{
                Text("Drag the green ball to the white ball")
                    .font(.largeTitle)
                    .bold()
                    .padding()
                
                Text("Try to follow the line")
                    .font(.title)
                    .bold()
                
                if appState.reachResult != ""{
                    HStack{
                    Text("Time")
                        Text(appState.reachResult)
                            .font(.body)
                            .padding()
                    }
                }
                
            }
        }
    }
}
