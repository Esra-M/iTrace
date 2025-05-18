//
//  VideoDownloader.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 15.05.25.
//

import Foundation
import AVFoundation
import UIKit

class VideoDownloader {
    static func exportHeatmapOverlayVideo(
        tapHistory: [(id: Int, timestamp: Double)],
        videoURL: URL,
        columns: Int,
        totalCells: Int,
        outputFileName: String,
        completion: @escaping (URL?) -> Void
    ) {
        let asset = AVAsset(url: videoURL)
        let composition = AVMutableComposition()

        guard let track = asset.tracks.first(where: { $0.mediaType.rawValue == AVMediaType.video.rawValue }) else {
            print("No video track found.")
            completion(nil)
            return
        }

        let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Failed to create mutable track.")
            completion(nil)
            return
        }

        do {
            try videoTrack.insertTimeRange(timeRange, of: track, at: .zero)
        } catch {
            print("Failed to insert track: \(error)")
            completion(nil)
            return
        }

        let videoSize = track.naturalSize
        let rows = totalCells / columns
        let cellWidth = videoSize.width / CGFloat(columns)
        let cellHeight = cellWidth
        let dotSize = cellWidth * 4

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: videoSize)
        overlayLayer.backgroundColor = UIColor.clear.cgColor

        for tap in tapHistory {
            let id = tap.id
            let timestamp = tap.timestamp
            let row = id / columns
            let column = id % columns

            guard row < rows, column < columns else { continue }

            let x = CGFloat(column) * cellWidth + (cellWidth - dotSize) / 2
            let y = videoSize.height - CGFloat(row + 1) * cellHeight + (cellHeight - dotSize) / 2

            let dotLayer = CALayer()
            dotLayer.frame = CGRect(x: x, y: y, width: dotSize, height: dotSize)
            dotLayer.cornerRadius = dotSize / 2
            dotLayer.opacity = 0

            let gradient = CAGradientLayer()
            gradient.frame = dotLayer.bounds
            gradient.colors = [
                UIColor.systemBlue.withAlphaComponent(0.8).cgColor,
                UIColor.clear.cgColor
            ]
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
            gradient.type = .radial
            dotLayer.backgroundColor = UIColor.systemBlue.cgColor
            dotLayer.mask = gradient

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.5
            fade.beginTime = AVCoreAnimationBeginTimeAtZero + timestamp - 0.25
            fade.autoreverses = true
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false

            dotLayer.add(fade, forKey: "fade")
            overlayLayer.addSublayer(dotLayer)
        }

        // Black background and red dots at the final frame
        let finalFrameStart = asset.duration - CMTime(seconds: 0.5, preferredTimescale: 600)
        let finalBlackLayer = CALayer()
        finalBlackLayer.frame = CGRect(origin: .zero, size: videoSize)
        finalBlackLayer.backgroundColor = UIColor.black.cgColor
        finalBlackLayer.opacity = 0

        let blackFade = CABasicAnimation(keyPath: "opacity")
        blackFade.fromValue = 0
        blackFade.toValue = 1
        blackFade.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(finalFrameStart)
        blackFade.duration = 0.1
        blackFade.fillMode = .forwards
        blackFade.isRemovedOnCompletion = false
        finalBlackLayer.add(blackFade, forKey: "blackFade")

        overlayLayer.addSublayer(finalBlackLayer)

        for tap in tapHistory {
            let id = tap.id
            let row = id / columns
            let column = id % columns

            guard row < rows, column < columns else { continue }

            let x = CGFloat(column) * cellWidth + (cellWidth - dotSize) / 2
            let y = videoSize.height - CGFloat(row + 1) * cellHeight + (cellHeight - dotSize) / 2

            let redDotLayer = CALayer()
            redDotLayer.frame = CGRect(x: x, y: y, width: dotSize, height: dotSize)
            redDotLayer.cornerRadius = dotSize / 2
            redDotLayer.opacity = 0

            let redGradient = CAGradientLayer()
            redGradient.frame = redDotLayer.bounds
            redGradient.colors = [
                UIColor.systemRed.withAlphaComponent(0.8).cgColor,
                UIColor.clear.cgColor
            ]
            redGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            redGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
            redGradient.type = .radial
            redDotLayer.backgroundColor = UIColor.systemRed.cgColor
            redDotLayer.mask = redGradient

            let redFade = CABasicAnimation(keyPath: "opacity")
            redFade.fromValue = 0
            redFade.toValue = 1
            redFade.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(finalFrameStart)
            redFade.duration = 0.1
            redFade.fillMode = .forwards
            redFade.isRemovedOnCompletion = false

            redDotLayer.add(redFade, forKey: "redFade")
            overlayLayer.addSublayer(redDotLayer)
        }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(outputFileName).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("Failed to create export session.")
            completion(nil)
            return
        }

        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.exportAsynchronously {
            if export.status == .completed {
                completion(outputURL)
            } else {
                print("Export failed: \(export.error?.localizedDescription ?? "Unknown error")")
                completion(nil)
            }
        }
    }
}

