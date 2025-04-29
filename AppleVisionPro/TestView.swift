//
//  TestView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 20.04.25.
//
import SwiftUI

struct TestView: View {
    
    @State private var typing = false

    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack {
            Text("Select a test")
                .padding(.bottom, 100)
                .font(.largeTitle)
                .bold()

            HStack(spacing: 50){
                VStack{
                    Image(systemName: "keyboard")
                        .font(.system(size: 50))
                        .padding()
                    
                    Button("Typing") {
                        typing = true
                    }
                    .font(.title)
                    .navigationDestination(isPresented: $typing) {
                        TypingView()
                    }
                }
                .frame(height: 150, alignment: .bottom)

                VStack{
                    Image(systemName: "dot.scope")
                        .font(.system(size: 50))
                    
                    Button("Selection") {
                        Task {
                            await dismissImmersiveSpace() // Close if anything's already active
                            try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s
                            await openImmersiveSpace(id: "Volume")
                        }
                    }
                    .font(.title)
                }
                .frame(height: 150, alignment: .bottom)
            }
        }
    }
}

#Preview(windowStyle: .automatic){
    TestView()
}
