//
//  ClickingView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 24.04.25.
//

import SwiftUI

struct ClickingView: View {
    @State private var clickCount = 0
    @State private var startTime: Date?
    @State private var endTime: Date?

    let totalClicks = 20

    
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            
            Button(action: {
                appState.currentPage = .test
            }) {
                Image(systemName: "chevron.backward")
                    .padding(20)
            }
            .offset(x: -580, y: -300)
            .frame(width: 60, height: 60)
            
            VStack(spacing: 40) {
                
                Text("Click on the circle until it's full")
                    .font(.largeTitle)
                
                ZStack {
                    Circle()
                        .fill(.gray)
                        .contentShape(Circle())
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: innerCircleSize, height: innerCircleSize)
                    
                }
                .frame(width: 200, height: 200)
                .gesture(
                    TapGesture().onEnded {
                        if clickCount < totalClicks {
                            handleTap()
                        }
                    }
                )
                
                VStack {
                    if clickCount == totalClicks, let start = startTime, let end = endTime {
                        let timeTaken = end.timeIntervalSince(start)
                        Text("Time: \(String(format: "%.2f", timeTaken)) seconds")
                            .font(.title2)
                    }
                }
                .frame(height: 40)
            }
            .padding(.top, 50)
        }
    }

    private var innerCircleSize: CGFloat {
        CGFloat(10 + (190.0 * Double(clickCount) / Double(totalClicks)))
    }

    private func handleTap() {
        if clickCount == 0 {
            startTime = Date()
        }
        if clickCount < totalClicks {
            clickCount += 1
        }
        if clickCount == totalClicks {
            endTime = Date()
        }
    }
}
