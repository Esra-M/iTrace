//
//  AppState.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 26.04.25.
//

import SwiftUI
import Combine

class AppState: ObservableObject {
    enum WindowPage {
        case content
        case keyboard
        case test
        case type
        case click
        case reach
        case select
        case eyeTracking
        case bullseyeTest
        case videoUpload
    }
    
    enum EyeTrackingMode {
        case normal
        case heatmapDisplay
    }
    @Published var currentPage: WindowPage = .content
    
    @Published var serverIPAddress: String = "192.168.0.109:5555"

    @Published var userName: String = ""
    @Published var videoName: String = ""
    @Published var clickData: [ClickData] = []
    @Published var heatmapVideoURL: URL?
    @Published var uploadedVideoURL: URL?
    @Published var eyeTrackingMode: EyeTrackingMode = .normal
    @Published var spatialTrackingData: [String: Any]?

    @Published var reachResult: String = ""
}
