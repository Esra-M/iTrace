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
    }

    @Published var currentPage: WindowPage = .test
    @Published var reachResult: String = ""
}

