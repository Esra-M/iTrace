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
    @State private var lastPressTime: Date? = nil
    @State private var timeSinceLastPress: TimeInterval? = nil
    @State private var lastPressedId: Int? = nil
    @State private var pressedCoordinates: (x: Int, y: Int)? = nil
    @State private var videoTimestamp: Double = 0
    @State private var tapCounts: [Int: Int] = [:]
    @State private var tapHistory: [(id: Int, timestamp: Double)] = []

    @State private var showHeatmap = false
    @State private var showLiveTapHighlights = false
    @State private var secondPlayStarted = false
    @State private var currentTime: Double = 0
    @State private var sliderValue: Double = 0
    @State private var displayedTime: Double = 0
    @State private var duration: Double = 0

    @State private var isExporting = false

    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 50)

    @State private var video = AVPlayer(url: Bundle.main.url(forResource: "backgroundVideo1", withExtension: "mp4")!)

    @State private var isPlaying: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VideoBackgroundView(player: video)
                    .colorMultiply((showHeatmap && currentTime >= duration) ? .black : (secondPlayStarted ? .gray : .white))
                    .ignoresSafeArea()
                    .disabled(true)

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(0..<1400, id: \.self) { id in
                        let row = id / 50
                        let column = id % 50
                        Rectangle()
                            .stroke(Color.black.opacity(0.5), lineWidth: 0)
                            .background(
                                ZStack {
                                    if showHeatmap && currentTime >= duration && tapCounts[id, default: 0] > 0 {
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    gradient: Gradient(colors: [vibrantHeatmapColor(for: tapCounts[id, default: 0], base: .red), .clear]),
                                                    center: .center,
                                                    startRadius: 0,
                                                    endRadius: geometry.size.width / 50 * 1.5
                                                )
                                            )
                                            .frame(width: geometry.size.width / CGFloat(columns.count) * 3,
                                                   height: geometry.size.width / CGFloat(columns.count) * 3)
                                    }

                                    if showLiveTapHighlights && currentTime < duration && isTapNearCurrentTime(id: id) {
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    gradient: Gradient(colors: [vibrantHeatmapColor(for: tapCounts[id, default: 0], base: .blue), .clear]),
                                                    center: .center,
                                                    startRadius: 0,
                                                    endRadius: geometry.size.width / 50 * 1.5
                                                )
                                            )
                                            .frame(width: geometry.size.width / CGFloat(columns.count) * 3,
                                                   height: geometry.size.width / CGFloat(columns.count) * 3)
                                    }
                                }
                            )
                            .frame(width: geometry.size.width / 50, height: geometry.size.width / 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !showHeatmap && !showLiveTapHighlights else { return }
                                let now = Date()
                                videoTimestamp = video.currentTime().seconds
                                if let last = lastPressTime {
                                    timeSinceLastPress = now.timeIntervalSince(last)
                                }
                                lastPressTime = now
                                lastPressedId = id
                                pressedCoordinates = (x: column, y: row)
                                tapCounts[id, default: 0] += 1
                                tapHistory.append((id: id, timestamp: videoTimestamp))
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: { appState.currentPage = .test }) {
                    Image(systemName: "chevron.backward")
                        .padding()
                }
                .clipShape(Circle())
                .offset(x: -580, y: -300)

                // Overlay during exporting
                if isExporting {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .allowsHitTesting(false) // So interactions with video still work

                    Text("Exporting...")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .transition(.opacity)
                }
            }
            .onAppear {
                Task {
                    if let asset = video.currentItem?.asset {
                        do {
                            let dur = try await asset.load(.duration)
                            duration = dur.seconds
                        } catch {
                            print("Failed to load duration: \(error)")
                        }
                    }
                }

                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    currentTime = video.currentTime().seconds
                    if isPlaying {
                        sliderValue = currentTime
                        displayedTime = currentTime
                    }
                }

                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object: video.currentItem,
                                                       queue: .main) { _ in
                    if !secondPlayStarted {
                        secondPlayStarted = true
                        showLiveTapHighlights = true
                        video.seek(to: .zero)
                        video.play()
                    } else {
                        showLiveTapHighlights = true
                        showHeatmap = true
                        isPlaying = false
                        video.pause()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomOrnament) {
                    HStack {
                        if !secondPlayStarted {
                            VStack(alignment: .leading, spacing: 4) {
                                if let timeSinceLastPress = timeSinceLastPress,
                                   let id = lastPressedId,
                                   let coords = pressedCoordinates {
                                    Text("ID: \(id) • Coordinates: (\(coords.x), \(coords.y))")
                                        .font(.footnote).bold()
                                    Text("Timestamp: \(String(format: "%.2f", videoTimestamp)) s")
                                        .font(.caption2)
                                    Text("Since last click: \(String(format: "%.2f", timeSinceLastPress)) s")
                                        .font(.caption2)
                                }
                            }
                        }

                        Button {
                            isPlaying ? video.pause() : video.play()
                            isPlaying.toggle()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title).bold().padding()
                        }

                        Slider(value: $sliderValue, in: 0...duration, onEditingChanged: { editing in
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
                            if video.timeControlStatus == .paused {
                                let time = CMTime(seconds: newValue, preferredTimescale: 600)
                                video.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                displayedTime = newValue
                            }
                        }
                        .frame(width: 300)

                        Text("\(String(format: "%.2f", sliderValue)) / \(String(format: "%.2f", duration))")
                            .font(.caption2)
                            .frame(width: 100)

                        if secondPlayStarted {
                            Button() {
                                guard !isExporting else { return }
                                isExporting = true

                                guard let videoURL = Bundle.main.url(forResource: "backgroundVideo1", withExtension: "mp4") else {
                                    print("Video not found.")
                                    isExporting = false
                                    return
                                }

                                let exportName = "backgroundVideo1_heatmap_export"

                                VideoDownloader.exportHeatmapOverlayVideo(
                                    tapHistory: tapHistory,
                                    videoURL: videoURL,
                                    columns: 50,
                                    totalCells: 1400,
                                    outputFileName: exportName
                                ) { exportedURL in
                                    DispatchQueue.main.async {
                                        isExporting = false
                                        guard let exportedURL = exportedURL else { return }

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
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.down.to.line.alt")
                            }
                            .help("Download Video with Heatmap")
                            .disabled(isExporting)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func isTapNearCurrentTime(id: Int) -> Bool {
        tapHistory.contains { $0.id == id && abs($0.timestamp - displayedTime) <= 0.5 }
    }

    private func vibrantHeatmapColor(for count: Int, base: Color) -> Color {
        switch count {
        case 1: return base.opacity(0.6)
        case 2: return base.opacity(0.7)
        case 3: return base.opacity(0.8)
        case 4: return base.opacity(0.9)
        default: return count >= 5 ? base.opacity(1) : .clear
        }
    }
}
