//
//  ImmersiveTrackingView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 13.05.25.
//

import SwiftUI
import RealityKit
import AVKit

struct ClickData: Codable {
    let x: Double
    let y: Double
    let timestamp: Double
}

struct ImmersiveTrackingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    @State private var tapLocation: CGPoint? = nil
    @State private var isRecording = false
    @State private var counterValue: Double = 0.00
    @State private var timer: Timer?
    @State private var recordingStartTime: Date?
    @State private var clickDataArray: [ClickData] = []
    @State private var isGeneratingHeatmap = false
    
    private let frameSize: CGSize = CGSize(width: 3300, height: 1860)

    var body: some View {
        RealityView { content, attachments in
            let headAnchor = AnchorEntity(.head)
            headAnchor.transform.translation = [-0.016, -0.038, -1.2]
            content.add(headAnchor)
            
            if let attachment = attachments.entity(for: "ui") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    headAnchor.addChild(attachment)
                }
            }
        } attachments: {
            Attachment(id: "ui") {
                ZStack {
                    if isRecording {
                        Rectangle()
                            .fill(Color.gray.opacity(0.001))
                            .frame(width: frameSize.width, height: frameSize.height)
                            .overlay(Rectangle().stroke(Color.blue, lineWidth: 5))
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onEnded { value in
                                        tapLocation = value.location
                                        if let startTime = recordingStartTime {
                                            let timestamp = Date().timeIntervalSince(startTime)
                                            clickDataArray.append(ClickData(
                                                x: Double(value.location.x),
                                                y: Double(value.location.y),
                                                timestamp: timestamp
                                            ))
                                            print("Clicked at (\(value.location.x), \(value.location.y)) at time \(timestamp)")
                                        }
                                    }
                            )

                        if let location = tapLocation {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                                .position(location)
                        }
                    }

                    VStack(spacing: 0) {
                        if isGeneratingHeatmap {
                            VStack(spacing: 30) {
                                Spacer()
                                VStack(spacing: 20) {
                                    ProgressView().scaleEffect(2.0)
                                    Text("Generating Heatmap...")
                                        .font(.title)
                                        .fontWeight(.bold)
                                }
                                .padding(50)
                                .background(.ultraThinMaterial)
                                .cornerRadius(25)
                                Spacer()
                            }
                        } else if isRecording {
                            HStack(spacing: 20) {
                                HStack(spacing: 15) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                        .scaleEffect(1.2)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                                    
                                    Text("RECORDING...")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text(String(format: "%.2f", counterValue))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 25)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                
                                Button(action: stopScreenRecording) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "stop.circle.fill")
                                            .font(.title2)
                                        Text("STOP")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                    }
                                    .padding(.horizontal, 25)
                                    .padding(.vertical, 15)
                                    .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.top, 50)
                        } else {
                            Spacer()
                            Button(action: startScreenRecording) {
                                HStack(spacing: 30) {
                                    Image(systemName: "record.circle")
                                        .font(.system(size: 80))
                                    Text("START RECORDING")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                }
                                .padding(40)
                            }
                        }
                        Spacer()
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                }
            }
        }
        .onDisappear {
            if isRecording { stopScreenRecording() }
        }
    }
    
    private func startScreenRecording() {
        isRecording = true
        recordingStartTime = Date()
        counterValue = 0.00
        tapLocation = nil
        clickDataArray.removeAll()
        appState.clickData.removeAll()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            if let startTime = recordingStartTime {
                counterValue = Date().timeIntervalSince(startTime)
            }
        }
        
        Task { await sendStartRecordingRequest() }
    }
    
    private func stopScreenRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        recordingStartTime = nil
        isGeneratingHeatmap = true
        print("Starting heatmap video generation...")
        
        Task { await sendStopRecordingRequest() }
    }
    
    private func sendStartRecordingRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress):5050/start_recording") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let requestBody = [
            "duration": 0,
            "continuous": true,
            "frame_width": Int(frameSize.width),
            "frame_height": Int(frameSize.height)
        ] as [String : Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            print("Recording started on server")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func sendStopRecordingRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress):5050/stop_recording") else {
            await MainActor.run { isGeneratingHeatmap = false }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0
        
        let requestBody = [
            "stop": true,
            "click_data": clickDataArray.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] },
            "frame_width": Int(frameSize.width),
            "frame_height": Int(frameSize.height)
        ] as [String : Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               httpResponse.mimeType == "video/mp4" {
                await handleReceivedVideoData(data)
            } else {
                await MainActor.run { isGeneratingHeatmap = false }
            }
        } catch {
            print("Failed to stop recording: \(error)")
            await MainActor.run { isGeneratingHeatmap = false }
        }
    }
    
    private func handleReceivedVideoData(_ data: Data) async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heatmap_\(UUID().uuidString).mp4")
        
        do {
            try data.write(to: tempURL)
            print("Heatmap video generated")
            
            await MainActor.run {
                appState.heatmapVideoURL = tempURL
                appState.clickData = clickDataArray
                
                appState.eyeTrackingMode = .heatmapDisplay
                
                openWindow(id: "main")
                appState.currentPage = .eyeTracking
                isGeneratingHeatmap = false
            }
            
            Task { await dismissImmersiveSpace() }
            
        } catch {
            print("Failed to save video file: \(error)")
            await MainActor.run { isGeneratingHeatmap = false }
        }
    }
}
