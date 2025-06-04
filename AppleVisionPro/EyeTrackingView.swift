//
//  EyeTrackingView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 28.04.25.
//

import SwiftUI
import AVFoundation

struct EyeTrackingView: View {
    @EnvironmentObject private var appState: AppState
    
    private static let videoFileName = "backgroundVideo"
    @State private var originalVideo = AVPlayer(url: Bundle.main.url(forResource: Self.videoFileName, withExtension: "mp4")!)
    @State private var activeVideo: AVPlayer?
    @State private var heatmapExportedURL: URL?
    @State private var lastPressTime: Date?
    @State private var pressedCoordinates: (x: CGFloat, y: CGFloat)?
    @State private var videoTimestamp: Double = 0
    @State private var tapHistory: [(x: Double, y: Double, timestamp: Double)] = []
    @State private var currentTime: Double = 0
    @State private var sliderValue: Double = 0
    @State private var displayedTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPreparingHeatmap = false
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var timeObserver: Any?
    @State private var timeObserverPlayer: AVPlayer?
    @State private var viewSize: CGSize = .zero
    @State private var videoSize: CGSize = .zero
    @State private var videoRect: CGRect = .zero
    
    private var isHeatmapDisplayMode: Bool { appState.eyeTrackingMode == .heatmapDisplay }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = activeVideo {
                    VideoBackgroundView(player: player) { calculatedVideoRect in
                        DispatchQueue.main.async {
                            self.videoRect = calculatedVideoRect
                        }
                    }
                    .colorMultiply(.white)
                    .ignoresSafeArea()
                    .disabled(true)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard !isPreparingHeatmap && !isHeatmapDisplayMode else { return }
                                let location = value.location
                                
                                let videoPercentages = convertScreenToVideoPercentages(
                                    screenPoint: location,
                                    viewSize: geometry.size,
                                    videoRect: videoRect
                                )
                                
                                guard let percentages = videoPercentages else {
                                    return
                                }
                                
                                videoTimestamp = originalVideo.currentTime().seconds
                                lastPressTime = Date()
                                
                                let pixelX = percentages.x * videoSize.width
                                let pixelY = percentages.y * videoSize.height
                                pressedCoordinates = (x: pixelX, y: pixelY)
                                
                                tapHistory.append((x: percentages.x, y: percentages.y, timestamp: videoTimestamp))
                                
                            }
                    )
                    .allowsHitTesting(!isPreparingHeatmap)

                if isPreparingHeatmap {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ProgressView("Generating heatmap")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
                }

                if isExporting {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ProgressView("Exporting")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
                }

                Button(action: {
                    activeVideo?.pause()
                    appState.eyeTrackingMode = .normal
                    appState.currentPage = .test
                }) {
                    Image(systemName: "chevron.backward").padding()
                }
                .clipShape(Circle())
                .offset(x: -580, y: -300)
            }
            .onAppear {
                viewSize = geometry.size
                setupVideo()
                loadVideoSize()
            }
            .onDisappear { cleanupPlayer() }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
                calculateVideoRect()
            }
            .onChange(of: appState.eyeTrackingMode) { _, newMode in
                newMode == .heatmapDisplay ? setupHeatmapVideo() : setupNormalVideo()
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    HStack {
                        if !isHeatmapDisplayMode && originalVideo == activeVideo, let coords = pressedCoordinates {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Eye Tracking Data").font(.footnote).bold()
                                Text(String(format: "Video Coords: (%.1f, %.1f)", coords.x, coords.y))
                                    .font(.caption2).frame(width: 220, alignment: .leading)
                                Text("Timestamp: \(formatTimestamp(videoTimestamp))")
                                    .font(.system(size: 11))
                            }
                        }
                        
                        Button {
                            isPlaying ? activeVideo?.pause() : activeVideo?.play()
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
                                let clampedTime = min(sliderValue, duration - 0.1)
                                let time = CMTime(seconds: clampedTime, preferredTimescale: 600)
                                
                                let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
                                video.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { finished in
                                    if finished && self.isPlaying {
                                        video.play()
                                    }
                                }
                            }
                        })
                        .onChange(of: sliderValue) { oldValue, newValue in
                            if let video = activeVideo, video.timeControlStatus == .paused {
                                let clampedTime = min(newValue, duration - 0.1)
                                let time = CMTime(seconds: clampedTime, preferredTimescale: 600)
                                let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
                                
                                video.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
                                    self.displayedTime = clampedTime
                                }
                            }
                        }
                        .frame(width: 300)
                        
                        Text("\(formatTime(sliderValue)) / \(formatTime(duration))")
                            .font(.caption2)
                            .frame(width: duration >= 3600 ? 150 : 100, alignment: .trailing)

                        if (isHeatmapDisplayMode && appState.heatmapVideoURL != nil) || heatmapExportedURL != nil {
                            Button {
                                exportVideo()
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
    
    
    private func loadVideoSize() {
        guard let videoURL = Bundle.main.url(forResource: Self.videoFileName, withExtension: "mp4") else { return }
        
        Task {
            let asset = AVAsset(url: videoURL)
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = tracks.first {
                    let size = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    
                    await MainActor.run {
                        let transformedSize = size.applying(transform)
                        self.videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                        calculateVideoRect()
                    }
                }
            } catch {
                print("Error loading video size: \(error)")
            }
        }
    }
    
    private func calculateVideoRect() {
        guard videoSize.width > 0 && videoSize.height > 0 && viewSize.width > 0 && viewSize.height > 0 else { return }
        
        let videoAspectRatio = videoSize.width / videoSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        if videoAspectRatio > viewAspectRatio {
            let scaledHeight = viewSize.width / videoAspectRatio
            let yOffset = (viewSize.height - scaledHeight) / 2
            videoRect = CGRect(x: 0, y: yOffset, width: viewSize.width, height: scaledHeight)
        } else {
            let scaledWidth = viewSize.height * videoAspectRatio
            let xOffset = (viewSize.width - scaledWidth) / 2
            videoRect = CGRect(x: xOffset, y: 0, width: scaledWidth, height: viewSize.height)
        }
    }
    
    private func convertScreenToVideoPercentages(screenPoint: CGPoint, viewSize: CGSize, videoRect: CGRect) -> CGPoint? {
        guard videoRect.contains(screenPoint) else {
            return nil
        }
        
        let relativeX = (screenPoint.x - videoRect.minX) / videoRect.width
        let relativeY = (screenPoint.y - videoRect.minY) / videoRect.height
        
        let clampedX = max(0.0, min(1.0, relativeX))
        let clampedY = max(0.0, min(1.0, relativeY))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
        
    private func setupVideo() {
        isHeatmapDisplayMode ? setupHeatmapVideo() : setupNormalVideo()
    }
    
    private func setupNormalVideo() {
        cleanupPlayerObserver()
        activeVideo = originalVideo
        setupPlayerObserver()
        loadDuration()
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: originalVideo.currentItem,
                                               queue: .main) { _ in
            if !isPreparingHeatmap && !isHeatmapDisplayMode {
                isPreparingHeatmap = true
                print("Starting heatmap video generation...")
                generateHeatmapVideo()
            }
        }
    }
    
    private func setupHeatmapVideo() {
        guard let heatmapURL = appState.heatmapVideoURL else { return }
        cleanupPlayerObserver()
        activeVideo = AVPlayer(url: heatmapURL)
        setupPlayerObserver()
        loadDuration()
        activeVideo?.play()
        isPlaying = true
    }
    
    private func setupPlayerObserver() {
        guard let player = activeVideo else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if isPlaying && !time.seconds.isNaN && time.seconds.isFinite {
                sliderValue = min(time.seconds, duration)
                displayedTime = sliderValue
            }
        }
        timeObserverPlayer = player
    }
    
    private func cleanupPlayerObserver() {
        if let observer = timeObserver, let player = timeObserverPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
            timeObserverPlayer = nil
        }
    }
    
    private func cleanupPlayer() {
        cleanupPlayerObserver()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func loadDuration() {
        Task {
            if let asset = activeVideo?.currentItem?.asset {
                do {
                    let dur = try await asset.load(.duration)
                    await MainActor.run { duration = dur.seconds }
                } catch {
                    print("Failed to load duration: \(error)")
                }
            }
        }
    }

    private func generateHeatmapVideo() {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/generate_heatmap"),
              let videoURL = Bundle.main.url(forResource: Self.videoFileName, withExtension: "mp4") else {
            print("Invalid URL or video file missing")
            isPreparingHeatmap = false
            return
        }
        
        let clicksPayload = tapHistory.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] }
        for (index, click) in clicksPayload.prefix(5).enumerated() {
            print("Click \(index + 1): \(click["x"]! * 100)%, \(click["y"]! * 100)% at \(click["timestamp"]!)s")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300.0
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: clicksPayload)
            data.append(formData(boundary: boundary, name: "clicks", value: jsonData))
        } catch {
            print("Error serializing click data: \(error)")
            isPreparingHeatmap = false
            return
        }
        
        do {
            let videoData = try Data(contentsOf: videoURL)
            data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"\(Self.videoFileName).mp4\"\r\nContent-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            data.append(videoData)
            data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        } catch {
            print("Error reading video file: \(error)")
            isPreparingHeatmap = false
            return
        }
        
        URLSession.shared.uploadTask(with: request, from: data) { responseData, response, error in
            DispatchQueue.main.async {
                self.isPreparingHeatmap = false
                
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let responseData = responseData else {
                    print("No response data received")
                    return
                }
                                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("heatmap_video.mp4")
                
                do {
                    try responseData.write(to: tempURL)
                    print("Heatmap video generated")
                    
                    self.cleanupPlayerObserver()
                    self.heatmapExportedURL = tempURL
                    self.activeVideo = AVPlayer(url: tempURL)
                    self.setupPlayerObserver()
                    self.activeVideo?.play()
                    self.isPlaying = true
                } catch {
                    print("Error saving heatmap video: \(error)")
                }
            }
        }.resume()
    }
    
    private func formData(boundary: String, name: String, value: String) -> Data {
        return "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!
    }
    
    private func formData(boundary: String, name: String, value: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append(value)
        data.append("\r\n".data(using: .utf8)!)
        return data
    }
    
    private func exportVideo() {
        isExporting = true
        let videoURL = isHeatmapDisplayMode ? appState.heatmapVideoURL : heatmapExportedURL
        let clickData = isHeatmapDisplayMode ?
            appState.clickData.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] } :
            tapHistory.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] }
        
        guard let exportedURL = videoURL else {
            isExporting = false
            return
        }
        
        var itemsToShare: [Any] = [exportedURL]
        
        if !clickData.isEmpty,
           let jsonData = try? JSONSerialization.data(withJSONObject: clickData, options: .prettyPrinted) {
            let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent("clicks.json")
            try? jsonData.write(to: jsonURL)
            itemsToShare.append(jsonURL)
        }
        
        let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            activityVC.popoverPresentationController?.sourceView = window
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            activityVC.popoverPresentationController?.permittedArrowDirections = []
            rootVC.present(activityVC, animated: true)
        }
        isExporting = false
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSecs = Int(seconds)
        let hrs = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        return hrs > 0 ? String(format: "%02d:%02d:%02d", hrs, mins, secs) : String(format: "%02d:%02d", mins, secs)
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let totalMillis = Int(seconds * 1000)
        let mins = totalMillis / 60000
        let secs = (totalMillis % 60000) / 1000
        let millis = (totalMillis % 1000) / 10
        return mins > 0 ? String(format: "%02d:%02d.%02d", mins, secs, millis) : String(format: "%02d.%02d", secs, millis)
    }
}

struct VideoBackgroundView: UIViewRepresentable {
    let player: AVPlayer
    let onVideoRectUpdate: (CGRect) -> Void
    
    func makeUIView(context: Context) -> PlayerView {
        let playerView = PlayerView()
        playerView.player = player
        playerView.onVideoRectUpdate = onVideoRectUpdate
        return playerView
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.player != player {
            uiView.player = player
        }
        uiView.onVideoRectUpdate = onVideoRectUpdate
    }
}

class PlayerView: UIView {
    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
        }
    }
    
    var onVideoRectUpdate: ((CGRect) -> Void)?
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspect
        
        if let player = player, let currentItem = player.currentItem {
            let videoSize = currentItem.presentationSize
            if videoSize.width > 0 && videoSize.height > 0 {
                let videoRect = calculateVideoRect(videoSize: videoSize, containerSize: bounds.size)
                onVideoRectUpdate?(videoRect)
            }
        }
    }
    
    private func calculateVideoRect(videoSize: CGSize, containerSize: CGSize) -> CGRect {
        let videoAspectRatio = videoSize.width / videoSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        if videoAspectRatio > containerAspectRatio {
            let scaledHeight = containerSize.width / videoAspectRatio
            let yOffset = (containerSize.height - scaledHeight) / 2
            return CGRect(x: 0, y: yOffset, width: containerSize.width, height: scaledHeight)
        } else {
            let scaledWidth = containerSize.height * videoAspectRatio
            let xOffset = (containerSize.width - scaledWidth) / 2
            return CGRect(x: xOffset, y: 0, width: scaledWidth, height: containerSize.height)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
    }
}
