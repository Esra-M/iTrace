//
//  ObjectDetectionView.swift
//  AppleVisionPro
//
//  Created by Assistant on 09.06.25.
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
    
    // For backward compatibility with tap location
    let x: Double?
    let y: Double?
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
        
        // Set x, y to nil since they come from bbox now
        x = nil
        y = nil
    }
    
    init(name: String, confidence: Double, bbox: BoundingBox?, timestamp: Double) {
        self.name = name
        self.confidence = confidence
        self.bbox = bbox
        self.timestamp = timestamp
        self.x = nil
        self.y = nil
    }
    
    // Fallback initializer for tap location (when no detection)
    init(name: String, confidence: Double, x: Double, y: Double, timestamp: Double) {
        self.name = name
        self.confidence = confidence
        self.bbox = nil
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }
}

struct ObjectDetectionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    @State private var tapLocation: CGPoint? = nil
    @State private var isDetecting = false
    @State private var detectedObjects: [DetectedObject] = []
    @State private var lastDetectedObject: DetectedObject? = nil
    @State private var isProcessingClick = false

    @State private var screenResolution: CGSize = CGSize(width: 3600, height: 2338)
    
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
                    if isDetecting {
                        Rectangle()
                            .fill(Color.gray.opacity(0.001))
                            .frame(width: frameSize.width, height: frameSize.height)
                            .overlay(Rectangle().stroke(Color.green, lineWidth: 0))
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onEnded { value in
                                        handleTap(at: value.location)
                                    }
                            )
                        
                        // Tap location indicator
                        if let location = tapLocation {
                            Circle()
                                .fill(Color.green.opacity(0.8))
                                .frame(width: 30, height: 30)
                                .position(location)
                                .animation(.easeOut(duration: 0.3), value: tapLocation)
                        }
                        
                        // Detected objects with bounding boxes
                        ForEach(detectedObjects) { object in
                            ZStack {
                                // Bounding box
                                if let bbox = object.bbox {
                                    let boxX = CGFloat(bbox.x) * frameSize.width
                                    let boxY = CGFloat(bbox.y) * frameSize.height
                                    let boxWidth = CGFloat(bbox.width) * frameSize.width
                                    let boxHeight = CGFloat(bbox.height) * frameSize.height
                                    
                                    Rectangle()
                                        .stroke(Color.green, lineWidth: 3)
                                        .fill(Color.green.opacity(0.1))
                                        .frame(width: boxWidth, height: boxHeight)
                                        .position(x: boxX + boxWidth / 2, y: boxY + boxHeight / 2)
                                        .animation(.easeOut(duration: 0.2), value: object.id)
                                    
                                    // Object label
                                    VStack(spacing: 4) {
                                        Text(object.name)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        Text(String(format: "%.1f%%", object.confidence * 100))
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.green.opacity(0.8))
                                    )
                                    .position(x: boxX + boxWidth / 2, y: max(boxY - 30, 20))
                                    .animation(.easeOut(duration: 0.2), value: object.id)
                                    
                                } else if let x = object.x, let y = object.y {
                                    // Fallback for tap location (no detection)
                                    VStack(spacing: 4) {
                                        Text(object.name)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        if object.confidence > 0 {
                                            Text(String(format: "%.1f%%", object.confidence * 100))
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.red.opacity(0.8))
                                    )
                                    .position(
                                        x: CGFloat(x) * frameSize.width,
                                        y: CGFloat(y) * frameSize.height
                                    )
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    
                    VStack(spacing: 0) {
                        if isDetecting {
                            HStack(spacing: 20) {
                                HStack(spacing: 15) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 20, height: 20)
                                        .scaleEffect(1.2)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDetecting)
                                    
                                    Text("REAL-TIME DETECTION")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 25)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                
                                Button(action: stopDetection) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "stop.circle.fill")
                                            .font(.largeTitle)
                                        Text("STOP")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                    }
                                    .padding(15)
                                }
                            }
                            .padding(.top, 200)
                            
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
                                
                                Text("Object Detection")
                                    .font(.largeTitle)
                                    .bold()
                                
                                Text("Identify and track objects around you")
                                    .font(.title)
                                    .padding(20)
                                
                                Text("Make sure View Mirroring is enabled")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .padding(20)
                                
                                Button(action: startDetection) {
                                    HStack(spacing: 20) {
                                        Image(systemName: "viewfinder")
                                            .font(.system(size: 40))
                                        Text("START DETECTION")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                    }
                                    .padding(20)
                                }
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
            }
        }
    }
    
    private func handleTap(at location: CGPoint) {
        guard !isProcessingClick else { return }
        
        tapLocation = location
        isProcessingClick = true
        
        let xPercentage = Double(location.x / frameSize.width)
        let yPercentage = Double(location.y / frameSize.height)
        
        let clampedX = max(0.0, min(1.0, xPercentage))
        let clampedY = max(0.0, min(1.0, yPercentage))
        
        print("Tapped at (\(clampedX), \(clampedY))")
        
        Task {
            await sendDetectionRequest(x: clampedX, y: clampedY)
        }
        
        // Clear tap location after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            tapLocation = nil
        }
    }
    
    private func startDetection() {
        isDetecting = true
        detectedObjects.removeAll()
        lastDetectedObject = nil
        
        Task {
            await sendStartDetectionRequest()
        }
    }
    
    private func stopDetection() {
        isDetecting = false
        isProcessingClick = false
        detectedObjects.removeAll()
        lastDetectedObject = nil
        
        Task {
            await sendStopDetectionRequest()
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
            print("Detection mode started")
        } catch {
            print("Failed to start detection: \(error)")
        }
    }
    
    private func sendStopDetectionRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/stop_detection") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            print("Detection mode stopped")
        } catch {
            print("Failed to stop detection: \(error)")
        }
    }
    
    private func sendDetectionRequest(x: Double, y: Double) async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/detect_object") else {
            await MainActor.run { isProcessingClick = false }
            return
        }
        
        let clickData = [
            "x": x,
            "y": y,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        request.httpBody = try? JSONSerialization.data(withJSONObject: clickData)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detectionsData = json["detections"] as? [[String: Any]] {
                    
                    await MainActor.run {
                        detectedObjects.removeAll()
                        
                        for detectionData in detectionsData {
                            if let name = detectionData["name"] as? String,
                               let confidence = detectionData["confidence"] as? Double {
                                
                                var detectedObject: DetectedObject
                                
                                // Check if bbox data exists
                                if let bboxData = detectionData["bbox"] as? [String: Any],
                                   let bboxX = bboxData["x"] as? Double,
                                   let bboxY = bboxData["y"] as? Double,
                                   let bboxWidth = bboxData["width"] as? Double,
                                   let bboxHeight = bboxData["height"] as? Double {
                                    
                                    let bbox = BoundingBox(x: bboxX, y: bboxY, width: bboxWidth, height: bboxHeight)
                                    detectedObject = DetectedObject(
                                        name: name,
                                        confidence: confidence,
                                        bbox: bbox,
                                        timestamp: Date().timeIntervalSince1970
                                    )
                                } else {
                                    // Fallback to tap location
                                    detectedObject = DetectedObject(
                                        name: name,
                                        confidence: confidence,
                                        x: x,
                                        y: y,
                                        timestamp: Date().timeIntervalSince1970
                                    )
                                }
                                
                                detectedObjects.append(detectedObject)
                                lastDetectedObject = detectedObject
                            }
                        }
                        
                        if detectedObjects.isEmpty {
                            // Show "Nothing detected" message at tap location
                            let noDetection = DetectedObject(
                                name: "Nothing detected",
                                confidence: 0.0,
                                x: x,
                                y: y,
                                timestamp: Date().timeIntervalSince1970
                            )
                            detectedObjects.append(noDetection)
                        }
                        
                        isProcessingClick = false
                        
                        // Clear detections after 5 seconds for better visibility
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            detectedObjects.removeAll()
                        }
                    }
                }
            } else {
                await MainActor.run { isProcessingClick = false }
            }
        } catch {
            print("Failed to detect object: \(error)")
            await MainActor.run { isProcessingClick = false }
        }
    }
}
