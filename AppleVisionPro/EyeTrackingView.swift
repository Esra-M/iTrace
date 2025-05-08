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

    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 50)
    
    @State private var video = AVPlayer(url: Bundle.main.url(forResource: "backgroundVideo", withExtension: "mp4")!)
    @State private var isPlaying: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Video
                VideoBackgroundView(player: video)
                    .ignoresSafeArea()
                    .disabled(true)

                
                VStack(spacing: 0) {
                    let squareSize = geometry.size.width / CGFloat(columns.count)

                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(0..<1400, id: \.self) { id in
                            let row = id / 50
                            let column = id % 50

                            Rectangle()
                                // BORDER
                                .stroke(Color.gray, lineWidth: 0)
                                .background(Color.clear)
                                .frame(width: squareSize, height: squareSize)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let now = Date()
                                    videoTimestamp = video.currentTime().seconds


                                    var timeString = ""
                                    if let last = lastPressTime {
                                        timeSinceLastPress = now.timeIntervalSince(last)
                                        timeString = String(format: "%.2f", timeSinceLastPress!)
                                    }
                                    lastPressTime = now
                                    lastPressedId = id
                                    pressedCoordinates = (x: column, y: row)

                                    print("ID: \(id) Coordinates: (\(column), \(row)) - Timestamp: \(String(format: "%.2f", videoTimestamp)) Sincle clicked: \(timeString)")
                                }
                        }
                    }                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: {
                    appState.currentPage = .test
                }) {
                    Image(systemName: "chevron.backward")
                }
                .clipShape(Circle())
                .offset(x: -580, y: -300)
            }
            .toolbar {
                ToolbarItem(placement: .bottomOrnament) {
                    HStack() {
                        VStack(alignment: .leading, spacing: 4) {
                            if let timeSinceLastPress = timeSinceLastPress,
                               let id = lastPressedId,
                               let coordinates = pressedCoordinates {
                                
                                Text("ID: \(id) • Coordinates: (\(coordinates.x), \(coordinates.y))")
                                    .font(.footnote)
                                    .bold()
                                
                                Text("Timestamp: \(String(format: "%.2f", videoTimestamp)) s")
                                    .font(.caption2)
                                
                                Text("Time since last click: \(String(format: "%.2f", timeSinceLastPress)) s")
                                    .font(.caption2)
                            }
                        }

                        Button {
                            isPlaying ? video.pause() : video.play()
                            isPlaying.toggle()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .bold()
                                .padding()
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
