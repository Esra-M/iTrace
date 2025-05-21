//
//  EyeTrackingView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 28.04.25.
//

import SwiftUI
import AVFoundation

struct VideoBackgroundView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            playerLayer.frame = view.bounds
        }

        view.layer.addSublayer(playerLayer)
        playerLayer.frame = view.bounds

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            playerLayer.player = player
            playerLayer.frame = uiView.bounds
        }
    }
}

struct EyeTrackingView: View {
    @EnvironmentObject private var appState: AppState

    private static let videoFileName = "backgroundVideo3"

    @State private var originalVideo = AVPlayer(url: Bundle.main.url(forResource: Self.videoFileName, withExtension: "mp4")!)

    @State private var activeVideo: AVPlayer? = nil
    @State private var heatmapExportedURL: URL? = nil

    @State private var lastPressTime: Date? = nil
    @State private var timeSinceLastPress: TimeInterval? = nil
    @State private var lastPressedId: Int? = nil
    @State private var pressedCoordinates: (x: Int, y: Int)? = nil
    @State private var videoTimestamp: Double = 0
    @State private var tapCounts: [Int: Int] = [:]
    @State private var tapHistory: [(x: Int, y: Int, timestamp: Double)] = []

    @State private var currentTime: Double = 0
    @State private var sliderValue: Double = 0
    @State private var displayedTime: Double = 0
    @State private var duration: Double = 0

    @State private var isPreparingHeatmap = false
    @State private var isPlaying = false
    @State private var showHeatmapImage = false
    @State private var heatmapImage: UIImage? = nil
    @State private var isExporting = false

    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 50)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = activeVideo, !showHeatmapImage {
                    VideoBackgroundView(player: player)
                        .colorMultiply(.white)
                        .ignoresSafeArea()
                        .disabled(true)
                }

                if showHeatmapImage, let image = heatmapImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                        .background(Color.black)
                }

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(0..<1400, id: \.self) { id in
                        let row = id / 50
                        let column = id % 50
                        Rectangle()
                            .stroke(Color.black.opacity(0.5), lineWidth: 0)
                            .background(Color.clear)
                            .frame(width: geometry.size.width / 50, height: geometry.size.width / 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !showHeatmapImage && !isPreparingHeatmap else { return }
                                let now = Date()
                                videoTimestamp = originalVideo.currentTime().seconds
                                if let last = lastPressTime {
                                    timeSinceLastPress = now.timeIntervalSince(last)
                                }
                                lastPressTime = now
                                lastPressedId = id
                                pressedCoordinates = (x: column, y: row)
                                tapCounts[id, default: 0] += 1
                                tapHistory.append((x: column, y: row, timestamp: videoTimestamp))
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(showHeatmapImage)

                if isPreparingHeatmap {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    ProgressView("Generating heatmap")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
                }

                if isExporting {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    ProgressView("Exporting...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
                }

                Button(action: { appState.currentPage = .test }) {
                    Image(systemName: "chevron.backward")
                        .padding()
                }
                .clipShape(Circle())
                .offset(x: -580, y: -300)
            }
            .onAppear {
                activeVideo = originalVideo
                Task {
                    if let asset = originalVideo.currentItem?.asset {
                        do {
                            let dur = try await asset.load(.duration)
                            duration = dur.seconds
                        } catch {
                            print("Failed to load duration: \(error)")
                        }
                    }
                }

                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let video = activeVideo {
                        currentTime = video.currentTime().seconds
                        if isPlaying {
                            sliderValue = currentTime
                            displayedTime = currentTime
                        }
                    }
                }

                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object: originalVideo.currentItem,
                                                       queue: .main) { _ in
                    if !showHeatmapImage && !isPreparingHeatmap {
                        isPreparingHeatmap = true
                        generateHeatmapVideo()
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    HStack {
                        if !showHeatmapImage {
                            VStack(alignment: .leading, spacing: 4) {
                                if let timeSinceLastPress = timeSinceLastPress,
                                   let id = lastPressedId,
                                   let coords = pressedCoordinates {
                                    Text("Eye Tracking Data")
                                        .font(.footnote).bold()
                                    Text("ID: \(id) • Coordinates: (\(coords.x), \(coords.y))")
                                        .font(.caption2)
                                        .frame(width: 250, alignment: .leading)
                                    Text("Timestamp: \(formatTimestamp(videoTimestamp)) • Since Last: \(formatTimestamp(timeSinceLastPress))")
                                        .font(.system(size: 11))
                                        .frame(width: 250, alignment: .leading)
                                }
                            }
                        }

                        Button {
                            if isPlaying {
                                activeVideo?.pause()
                            } else {
                                activeVideo?.play()
                            }
                            isPlaying.toggle()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title).bold().padding()
                        }

                        Slider(value: $sliderValue, in: 0...duration, onEditingChanged: { editing in
                            guard let video = activeVideo else { return }
                            if editing {
                                video.pause()
                            } else {
                                let time = CMTime(seconds: sliderValue, preferredTimescale: 600)
                                video.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                if isPlaying {
                                    video.play()
                                }
                            }
                        })
                        .onChange(of: sliderValue) { oldValue, newValue in
                            if let video = activeVideo, video.timeControlStatus == .paused {
                                let time = CMTime(seconds: newValue, preferredTimescale: 600)
                                video.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                displayedTime = newValue
                            }
                        }
                        .frame(width: 300)
                        
                        let needsHour = Int(duration) >= 3600

                        let fixedWidth: CGFloat = {
                            if needsHour {
                                return 150
                            } else {
                                return 100
                            }
                        }()

                        let formatTime: (Double) -> String = { seconds in
                            let totalSecs = Int(seconds)
                            let hrs = totalSecs / 3600
                            let mins = (totalSecs % 3600) / 60
                            let secs = totalSecs % 60

                            if needsHour {
                                return String(format: "%02d:%02d:%02d", hrs, mins, secs)
                            } else {
                                return String(format: "%02d:%02d", mins, secs)
                            }
                        }

                        Text("\(formatTime(sliderValue)) / \(formatTime(duration))")
                            .font(.caption2)
                            .frame(width: fixedWidth, alignment: .trailing)


                        
                        if heatmapExportedURL != nil {
                            Button {
                                isExporting = true
                                DispatchQueue.main.async {
                                    guard let exportedURL = heatmapExportedURL else { return }
                                    let activityVC = UIActivityViewController(activityItems: [exportedURL], applicationActivities: nil)
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let window = windowScene.windows.first,
                                       let rootVC = window.rootViewController {
                                        activityVC.popoverPresentationController?.sourceView = window
                                        activityVC.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX,
                                                                                                      y: window.bounds.midY,
                                                                                                      width: 0,
                                                                                                      height: 0)
                                        activityVC.popoverPresentationController?.permittedArrowDirections = []
                                        rootVC.present(activityVC, animated: true)
                                    }
                                    isExporting = false
                                }
                            } label: {
                                Label("Download", systemImage: "arrow.down.to.line.alt")
                            }
                            .padding(.leading, 10)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func generateHeatmapVideo() {
        guard let url = URL(string: "http://192.168.0.107:5050/generate_heatmap_video"),
              let videoURL = Bundle.main.url(forResource: Self.videoFileName, withExtension: "mp4") else {
            print("Invalid URL or video file missing")
            return
        }

        isPreparingHeatmap = true

        let clicksPayload = tapHistory.map { ["row": $0.y, "col": $0.x, "timestamp": $0.timestamp] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()

        let jsonData = try! JSONSerialization.data(withJSONObject: clicksPayload)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"clicks\"\r\n\r\n".data(using: .utf8)!)
        data.append(jsonData)
        data.append("\r\n".data(using: .utf8)!)

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"rows\"\r\n\r\n28\r\n".data(using: .utf8)!)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"cols\"\r\n\r\n50\r\n".data(using: .utf8)!)

        let videoData = try! Data(contentsOf: videoURL)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"video\"; filename=\"video.mp4\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        data.append(videoData)
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = data

        URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
            DispatchQueue.main.async {
                isPreparingHeatmap = false
                if let data = data {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("heatmap_video.mp4")
                    try? data.write(to: tempURL)
                    self.heatmapExportedURL = tempURL
                    self.activeVideo = AVPlayer(url: tempURL)
                    self.activeVideo?.play()
                    self.isPlaying = true
                    self.showHeatmapImage = false
                } else {
                    print("Error:", error?.localizedDescription ?? "Unknown")
                }
            }
        }.resume()
    }
    
    let formatTimestamp: (Double) -> String = { seconds in
        let totalMillis = Int(seconds * 1000)
        let hrs = totalMillis / (3600 * 1000)
        let mins = (totalMillis % (3600 * 1000)) / (60 * 1000)
        let secs = (totalMillis % (60 * 1000)) / 1000
        let millis = (totalMillis % 1000) / 10

        if hrs > 0 {
            return String(format: "%02d:%02d:%02d.%02d", hrs, mins, secs, millis)
        } else if mins > 0 {
            return String(format: "%02d:%02d.%02d", mins, secs, millis)
        } else {
            return String(format: "%02d.%02d", secs, millis)
        }
    }

}
