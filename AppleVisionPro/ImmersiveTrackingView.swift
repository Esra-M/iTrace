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
    @State private var screenResolution: CGSize = CGSize(width: 3600, height: 2338)
    
    @State private var stopButtonPressProgress: CGFloat = 0
    @State private var stopButtonTimer: Timer?
    @State private var isStopButtonPressed = false
    
    private let stopButtonPressDuration: Double = 2.0
    
    private var frameSize: CGSize {
        CGSize(
            width: screenResolution.width * 0.911,
            height: screenResolution.height * 0.789
        )
    }

    var body: some View {
        RealityView { content, attachments in
            let headAnchor = AnchorEntity(.head)
            headAnchor.transform.translation = [-0.02, -0.038, -1.2]
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
                                            
                                            let xPercentage = Double(value.location.x / frameSize.width)
                                            let yPercentage = Double(value.location.y / frameSize.height)
                                            
                                            let clampedX = max(0.0, min(1.0, xPercentage))
                                            let clampedY = max(0.0, min(1.0, yPercentage))
                                            
                                            clickDataArray.append(ClickData(
                                                x: clampedX,
                                                y: clampedY,
                                                timestamp: timestamp
                                            ))
                                            print("Clicked at (\(clampedX * 100)%, \(clampedY * 100)%) at time \(timestamp)")
                                        }
                                    }
                            )

                        if let location = tapLocation {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 40, height: 40)
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
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                    
                                    let minutes = Int(counterValue) / 60
                                    let seconds = counterValue.truncatingRemainder(dividingBy: 60)
                                    Text(String(format: "%02d.%05.2f", minutes, seconds))
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 25)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                
                                ZStack {
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                        .frame(width: 185, height: 80)
                                    
                                    RoundedRectangle(cornerRadius: 25)
                                        .trim(from: 0, to: stopButtonPressProgress)
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: 80, height: 185)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear(duration: 0.1), value: stopButtonPressProgress)
                                    
                                    Button(action: {}) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "stop.circle.fill")
                                                .font(.largeTitle)
                                            Text("STOP")
                                                .font(.largeTitle)
                                                .fontWeight(.bold)
                                        }
                                        .padding(.horizontal, 25)
                                        .padding(.vertical, 15)
                                        .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { _ in
                                                if !isStopButtonPressed {
                                                    startStopButtonPress()
                                                }
                                            }
                                            .onEnded { _ in
                                                stopStopButtonPress()
                                            }
                                    )
                                }
                            }
                            .padding(.top, 100)
                        } else {
                            Spacer()
                            VStack{
                                Button(action: {
                                    Task {
                                        await MainActor.run {
                                            appState.currentPage = .test
                                        }
                                        await dismissImmersiveSpace()
                                        openWindow(id: "main")
                                    }
                                }) {
                                    Image(systemName: "chevron.backward")
                                        .font(.system(size: 24))
                                        .padding()
                                }
                                .clipShape(Circle())
                                .offset(x: -290, y: 10)
                                
                                Text("Before you start, anable View Mirroring")
                                    .font(.largeTitle)
                                    .padding(60)
                                
                                Button(action: startScreenRecording) {
                                    HStack(spacing: 20) {
                                        Image(systemName: "record.circle")
                                            .font(.system(size: 40))
                                        Text("START")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                    }
                                    .padding(20)
                                }
                                .padding(20)
                            }
                            .frame(width: 700, height: 400)
                            .glassBackgroundEffect()
                        }
                        Spacer()
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                }
            }
        }
        .onAppear {
            Task {
                await fetchScreenResolution()
            }
        }
        .onDisappear {
            stopStopButtonPress()
        }
//        .onDisappear {
//            if isRecording { stopScreenRecording() }
//        }
    }
    
    private func startStopButtonPress() {
        isStopButtonPressed = true
        stopButtonPressProgress = 0
        
        stopButtonTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            stopButtonPressProgress += 0.05 / stopButtonPressDuration
            
            if stopButtonPressProgress >= 1.0 {
                stopScreenRecording()
                stopStopButtonPress()
            }
        }
    }
    
    private func stopStopButtonPress() {
        isStopButtonPressed = false
        stopButtonTimer?.invalidate()
        stopButtonTimer = nil
        stopButtonPressProgress = 0
    }
    
    private func fetchScreenResolution() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/get_screen_resolution") else {
            print("Invalid server URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let width = json["width"] as? Int,
               let height = json["height"] as? Int {
                
                await MainActor.run {
                    screenResolution = CGSize(width: CGFloat(width), height: CGFloat(height))
                    print("Screen resolution updated: \(width)×\(height)")
                }
            } else {
                print("No screen resolution data available, using default")
            }
        } catch {
            print("Failed to fetch screen resolution: \(error)")
            print("Using default resolution: \(Int(screenResolution.width))×\(Int(screenResolution.height))")
        }
    }
    
    private func startScreenRecording() {
        isRecording = true
        recordingStartTime = Date()
        counterValue = 0.00
        tapLocation = nil
        clickDataArray.removeAll()
        appState.clickData.removeAll()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
                if let startTime = self.recordingStartTime {
                    self.counterValue = Date().timeIntervalSince(startTime) - 0.4
                    if self.counterValue < 0 {
                        self.counterValue = 0.00
                    }
                }
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
        guard let url = URL(string: "http://\(appState.serverIPAddress)/start_recordin") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let requestBody = [
            "duration": 0,
            "continuous": true
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
        guard let url = URL(string: "http://\(appState.serverIPAddress)/stop_recording") else {
            await MainActor.run { isGeneratingHeatmap = false }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0
        
        let requestBody = [
            "stop": true,
            "click_data": clickDataArray.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] }
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
