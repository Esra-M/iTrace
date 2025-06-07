//
//  SelectionView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 23.04.25.
//

import SwiftUI

struct SelectionView: View {
    
    
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace // 👈 Add this!

    
    var body: some View {
        ZStack {
            
            Button(action: {
                appState.currentPage = .test
                Task {
                    await dismissImmersiveSpace()
                }
            }) {
                Image(systemName: "chevron.backward")
                    .padding(20)
            }
            .offset(x: -580, y: -300)
            .frame(width: 60, height: 60)
            
            
            Text("Select all the spheres by clicking on them")
        }
    }
}
