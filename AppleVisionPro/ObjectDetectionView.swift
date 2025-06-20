//
//  ObjectDetectionView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 09.06.25.
//

import SwiftUI
import RealityKit
import AVKit

struct BoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct DetectedObject: Codable, Identifiable {
    let id = UUID()
    let name: String
    let confidence: Double
    let bbox: BoundingBox?
    let timestamp: Double
    
    private enum CodingKeys: String, CodingKey {
        case name, confidence, bbox, timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        confidence = try container.decode(Double.self, forKey: .confidence)
        bbox = try container.decodeIfPresent(BoundingBox.self, forKey: .bbox)
        timestamp = try container.decode(Double.self, forKey: .timestamp)
    }
    
    init(name: String, confidence: Double, bbox: BoundingBox?, timestamp: Double) {
        self.name = name
        self.confidence = confidence
        self.bbox = bbox
        self.timestamp = timestamp
    }
}

struct ObjectDetectionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    @State private var isDetecting = false
    @State private var isLoading = false
    @State private var detectedObjects: [DetectedObject] = []
    @State private var detectionTimer: Timer? = nil
    @State private var screenResolution: CGSize = CGSize(width: 3600, height: 2338)
    @State private var isVideoAnalysisReady = false
    @State private var detectionStatus = "Initializing..."
    @State private var isGeneratingResult = false
    @State private var backgroundGeneration = false
    
    @State private var stopButtonPressProgress: CGFloat = 0
    @State private var stopButtonTimer: Timer?
    @State private var isStopButtonPressed = false
    @State private var showPressHoldHint = false
    @State private var hintTimer: Timer?
    
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
            headAnchor.transform.translation = [-0.022, -0.038, -1.2]
            content.add(headAnchor)
            
            if let attachment = attachments.entity(for: "ui") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    headAnchor.addChild(attachment)
                }
            }
        } attachments: {
            Attachment(id: "ui") {
                ZStack {
                    if isDetecting && isVideoAnalysisReady {
                        Rectangle()
                            .fill(Color.gray.opacity(0.001))
                            .frame(width: frameSize.width, height: frameSize.height)
                            .overlay(Rectangle().stroke(Color.blue, lineWidth: 0))
                        
                        ForEach(detectedObjects) { object in
                            if let bbox = object.bbox {
                                let boxX = CGFloat(bbox.x) * frameSize.width
                                let boxY = CGFloat(bbox.y) * frameSize.height
                                let boxWidth = CGFloat(bbox.width) * frameSize.width
                                let boxHeight = CGFloat(bbox.height) * frameSize.height
                                let centerX = boxX + boxWidth / 2
                                let centerY = boxY + boxHeight / 2
                                
                                ZStack {
                                    Rectangle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .fill(Color.blue.opacity(0.05))
                                        .frame(width: boxWidth, height: boxHeight)
                                        .position(x: centerX, y: centerY)
                                        .animation(.easeOut(duration: 0.3), value: object.id)
                                    
                                    VStack(spacing: 4) {
                                        Text(object.name)
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                        Text(String(format: "%.1f%%", object.confidence * 100))
                                            .font(.title)
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.8))
                                    )
                                    .position(x: centerX, y: centerY)
                                    .animation(.easeOut(duration: 0.3), value: object.id)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    
                    VStack(spacing: 0) {
                        if isGeneratingResult {
                            VStack(spacing: 30) {
                                Spacer()
                                
                                VStack(spacing: 20) {
                                    ProgressView().scaleEffect(2.0)
                                        .padding(.top, 30)
                                    
                                    Text("Generating Video")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .padding()
                                    
                                    Button(action: {
                                        generateInBackground()
                                    }) {
                                        Text("Generate in Background")
                                            .font(.title2)
                                            .padding()
                                    }
                                }
                                .frame(width: 500)
                                .padding(40)
                                .glassBackgroundEffect()
                                .cornerRadius(25)
                                
                                Spacer()
                            }
                        } else if isDetecting && isVideoAnalysisReady {
                            HStack(spacing: 20) {
                                HStack(spacing: 15) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 20, height: 20)
                                        .scaleEffect(1.2)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDetecting)
                                    
                                    Text("OBJECT DETECTION")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 25)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                
                                ZStack {
                                    RoundedRectangle(cornerRadius: 50)
                                        .trim(from: 0, to: stopButtonPressProgress)
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: 70, height: 208)
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
                                        .padding(15)
                                    }
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { _ in
                                                if !isStopButtonPressed {
                                                    startStopButtonPress()
                                                    showPressHoldHint = true
                                                    hintTimer?.invalidate()
                                                    hintTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                                                        showPressHoldHint = false
                                                    }
                                                }
                                            }
                                            .onEnded { _ in
                                                stopStopButtonPress()
                                            }
                                    )
                                    
                                    if showPressHoldHint {
                                        Text("Press and Hold")
                                            .font(.system(size: 25))
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                            .offset(y: 80)
                                            .bold()
                                    }
                                }
                                .onDisappear {
                                    hintTimer?.invalidate()
                                }
                            }
                            .padding(.top, 300)
                            
                        } else {
                            Spacer()
                            VStack() {
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
                                        .padding(20)
                                }
                                .frame(width: 60, height: 60)
                                .offset(x: -340, y: 20)
                                
                                Text("Video Object Detection")
                                    .font(.largeTitle)
                                    .bold()
                                
                                Text("Identify objects around you")
                                    .font(.title)
                                    .padding(20)
                                
                                VStack(spacing: 10) {
                                    Text("Make sure View Mirroring is enabled")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                    
                                }
                                .padding(20)
                                
                                Button(action: startDetection) {
                                    HStack(spacing: 20) {
                                        if isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(1.5)
                                        } else {
                                            Image(systemName: "record.circle")
                                                .font(.system(size: 40))
                                        }
                                        
                                        Text(isLoading ? "LOADING" : "START RECORDING")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(20)
                                }
                                .disabled(isLoading)
                                .padding(40)
                            }
                            .frame(width: 800, height: 450)
                            .glassBackgroundEffect()
                        }
                        Spacer()
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                }
            }
        }
        .onDisappear {
            if isDetecting {
                stopDetection()
                generateInBackground()
            }
            hintTimer?.invalidate()
            stopButtonTimer?.invalidate()
        }
    }
    
    private func generateInBackground() {
        backgroundGeneration = true
        print("Generating object detection video in background")
        Task {
            await dismissImmersiveSpace()
            await MainActor.run {
                appState.currentPage = .test
            }
            openWindow(id: "main")
        }
    }
    
    private func startStopButtonPress() {
        isStopButtonPressed = true
        stopButtonPressProgress = 0
        
        stopButtonTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            stopButtonPressProgress += 0.05 / stopButtonPressDuration
            
            if stopButtonPressProgress >= 1.0 {
                stopDetection()
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
    
    private func startDetection() {
        isLoading = true
        isDetecting = true
        isVideoAnalysisReady = false
        detectedObjects.removeAll()
        detectionStatus = "Initializing detection system..."
        
        Task {
            await sendStartDetectionRequest()
            
            try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds static
            await MainActor.run {
                isLoading = false
                isVideoAnalysisReady = true
                detectionStatus = "Analyzing video stream..."
                
                detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    Task {
                        await fetchDetections()
                    }
                }
            }
        }
    }
    
    private func stopDetection() {
        guard !isGeneratingResult else { return }
        
        isDetecting = false
        isLoading = false
        isVideoAnalysisReady = false
        detectedObjects.removeAll()
        detectionStatus = "Processing..."
        isGeneratingResult = true
        
        detectionTimer?.invalidate()
        detectionTimer = nil
        
        print("Starting object detection video processing...")
        
        Task {
            await sendStopDetectionRequest()
        }
    }
    
    private func fetchDetections() async {
        guard isDetecting && !isLoading && isVideoAnalysisReady else { return }
        
        guard let url = URL(string: "http://\(appState.serverIPAddress)/get_detections") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detectionsData = json["detections"] as? [[String: Any]] {
                    
                    await MainActor.run {
                        var newDetections: [DetectedObject] = []
                        
                        for detectionData in detectionsData {
                            if let name = detectionData["name"] as? String,
                               let confidence = detectionData["confidence"] as? Double,
                               let bboxData = detectionData["bbox"] as? [String: Any],
                               let bboxX = bboxData["x"] as? Double,
                               let bboxY = bboxData["y"] as? Double,
                               let bboxWidth = bboxData["width"] as? Double,
                               let bboxHeight = bboxData["height"] as? Double {
                                
                                let bbox = BoundingBox(x: bboxX, y: bboxY, width: bboxWidth, height: bboxHeight)
                                let detectedObject = DetectedObject(
                                    name: name,
                                    confidence: confidence,
                                    bbox: bbox,
                                    timestamp: Date().timeIntervalSince1970
                                )
                                
                                newDetections.append(detectedObject)
                            }
                        }
                        
                        withAnimation(.easeInOut(duration: 0.2)) {
                            detectedObjects = newDetections
                        }
                    }
                }
            }
        } catch {
            print("Failed to fetch detections: \(error)")
        }
    }
    
    private func sendStartDetectionRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/start_detection") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            print("Video-based detection started")
        } catch {
            print("Failed to start detection: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func sendStopDetectionRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/stop_detection") else {
            await MainActor.run { isGeneratingResult = false }
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let trackingData = [
            "user_name": appState.userName,
            "user_age": appState.userAge,
            "user_gender": appState.userGender,
            "timestamp": timestamp,
            "tracking_type": "object_detection"
        ] as [String : Any]
        
        let requestBody = [
            "tracking_data": trackingData,
            "return_video": !backgroundGeneration
        ] as [String : Any]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               httpResponse.mimeType == "video/mp4" {
                
                if !backgroundGeneration {
                    await handleReceivedVideoData(data, response: httpResponse, trackingData: trackingData)
                }
            } else {
                await MainActor.run { isGeneratingResult = false }
            }
        } catch {
            print("Failed to stop detection: \(error)")
            await MainActor.run { isGeneratingResult = false }
        }
    }
    
    private func handleReceivedVideoData(_ data: Data, response: HTTPURLResponse, trackingData: [String: Any]) async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("object_detection_\(UUID().uuidString).mp4")
        
        do {
            try data.write(to: tempURL)
            print("Object detection video processed")
            
            var sessionData: [String: Any] = trackingData
            if let sessionDataHeader = response.allHeaderFields["X-Session-Data"] as? String,
               let sessionDataFromServer = try? JSONSerialization.jsonObject(with: sessionDataHeader.data(using: .utf8) ?? Data()) as? [String: Any] {
                sessionData = sessionDataFromServer
            }
            
            await dismissImmersiveSpace()

            await MainActor.run {
                appState.VideoURL = tempURL
                appState.videoData = sessionData
                
                if let detectedObjects = sessionData["detected_objects"] as? [[String: Any]] {
                    appState.clickData = detectedObjects.compactMap { detection in
                        guard let bbox = detection["bounding_box"] as? [String: Any],
                              let x = bbox["x"] as? Double,
                              let y = bbox["y"] as? Double,
                              let timestamp = detection["timestamp"] as? Double else {
                            return nil
                        }
                        
                        let width = bbox["width"] as? Double ?? 0
                        let height = bbox["height"] as? Double ?? 0
                        let centerX = x + width / 2
                        let centerY = y + height / 2
                        
                        return ClickData(x: centerX, y: centerY, timestamp: timestamp)
                    }
                } else {
                    appState.clickData = []
                }
                
                appState.eyeTrackingMode = .display
                appState.currentPage = .eyeTracking
                
                isGeneratingResult = false
                
                openWindow(id: "main")
            }
            
        } catch {
            print("Failed to save video file: \(error)")
            await MainActor.run { isGeneratingResult = false }
        }
    }
}
