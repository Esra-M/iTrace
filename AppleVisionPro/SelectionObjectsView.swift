//
//  selection.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 23.04.25.
//

import SwiftUI
import RealityKitContent
import RealityKit

struct SelectionObjectsView: View {
    var body: some View {
        RealityView {content in
            if let scene = try? await Entity(named: "Scene", in: realityKitContentBundle) {
                scene.position = [0, 1.5, -1.0]
                content.add(scene)
            }
        }
    }
}

#Preview () {
    SelectionObjectsView()
}
