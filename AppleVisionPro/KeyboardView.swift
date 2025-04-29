//
//  Keyboard.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 21.04.25.
//

import SwiftUI

struct KeyboardView: View {
    
    @State private var done = false

    var body: some View {
        VStack {
            HStack(spacing: 30) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 50))
                Text("Keyboard & Mouse")
                    .font(.title)
            
            }
            Text("To continue conntect to a keyboard and a mouse")
                .padding()
            
            Button("Done") {
                done = true
            }
            .font(.title)
            .padding()    
            .navigationDestination(isPresented: $done) {
                TestView()
            }
        }
    }
}

#Preview(windowStyle: .automatic){
    KeyboardView()
}
