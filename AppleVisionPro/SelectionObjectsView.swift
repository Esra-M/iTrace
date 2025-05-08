//
//  selection.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 23.04.25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct SelectionObjectsView: View {

    var body: some View {
        RealityView { content in
            for _ in 0..<10 {
                if let model = try? await Entity(named: "SphereA", in: realityKitContentBundle) {
                    model.position = [
                        Float.random(in: -1.5...1.5),
                        Float.random(in: 1.0...2.0),
                        Float.random(in: -1.5...(-1.0))
                    ]
                    model.generateCollisionShapes(recursive: true)
                    model.components.set(InputTargetComponent())
                    model.components.set(PhysicsBodyComponent(massProperties: .default, material: .default, mode: .dynamic))
                    content.add(model)
                }
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    value.entity.removeFromParent()
                }
        )
    }
}
