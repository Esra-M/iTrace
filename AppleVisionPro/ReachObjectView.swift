//  ImmersiveView.swift
//  NewDimensionn
//
//  Created by Patrick Schnitzer on 18.07.23.
import SwiftUI
import RealityKit
import RealityKitContent
import Combine

struct ReachObjectView: View {
    @State private var timer: Timer?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timerStartDate: Date?
    @State private var activeLineCollisions = 0
    
    @EnvironmentObject private var appState: AppState
    
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack {
            RealityView { content in
                async let sphereAAsync = Entity(named: "SphereA", in: realityKitContentBundle)
                async let sphereBAsync = Entity(named: "SphereB", in: realityKitContentBundle)
                
                if let sphereA = try? await sphereAAsync,
                   let sphereB = try? await sphereBAsync {
                    
                    sphereA.position = [-2.0, 0, -2.0]
                    sphereB.position = [ 2.0, 0, -2.0]
                    
                    sphereA.generateCollisionShapes(recursive: true)
                    sphereB.generateCollisionShapes(recursive: true)
                    
                    sphereA.components.set(InputTargetComponent())
                    sphereB.components.set(InputTargetComponent())
 
                    content.add(sphereA)
                    content.add(sphereB)
                    
                    let line = createStaticLine(from: sphereA.position, to: sphereB.position)
                    line.generateCollisionShapes(recursive: true)
                    line.components.set(InputTargetComponent())
                    content.add(line)
                   
                    content.subscribe(to: CollisionEvents.Began.self) { event in
                        let a = event.entityA.name
                        let b = event.entityB.name
                        
                        if (a == "SphereA" && b == "SphereB") || (a == "SphereB" && b == "SphereA") {
                            DispatchQueue.main.async {
                                appState.reachResult = String(format: "%.2f", elapsedTime)
                                appState.currentPage = .reach
                                Task { await dismissImmersiveSpace() }
                            }
                        }
                        
                        else if (a == "SphereA" && b == "Line") || (a == "Line" && b == "SphereA") {
                            
                            activeLineCollisions += 1
                            
                            startTimer()
                            
                            if let a = sphereA.findEntity(named: "SphereA"),
                               var model = a.components[ModelComponent.self],
                               var material = model.materials.first as? PhysicallyBasedMaterial {
                                material.baseColor.tint = UIColor(red: 0.5, green: 1.0, blue: 0.5, alpha: 1.0)
                                model.materials = [material]
                                a.components.set(model)
                            }
                        }
                    }
                    
                    content.subscribe(to: CollisionEvents.Ended.self) { event in
                        let a = event.entityA.name
                        let b = event.entityB.name

                        if (a == "SphereA" && b == "Line") || (a == "Line" && b == "SphereA") {
                           
                            activeLineCollisions -= 1

                            if activeLineCollisions <= 0 {
                                pauseTimer()
                                
                                if let a = sphereA.findEntity(named: "SphereA"),
                                   var model = a.components[ModelComponent.self],
                                   var material = model.materials.first as? PhysicallyBasedMaterial {
                                    material.baseColor.tint = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)
                                    model.materials = [material]
                                    a.components.set(model)
                                }
                            }
                        }
                    }
                    
                }
            }
            .gesture(dragGesture)
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
        .targetedToAnyEntity()
        .onChanged { value in
            let entity = value.entity
            if entity.name == "SphereA" {
                entity.position = value.convert(
                    value.location3D,
                    from: .local,
                    to: entity.parent!
                )
            }
        }
    }

    private func createStaticLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Entity {
        let entity = Entity()
        
        let totalDistance = simd_distance(start, end)
        let direction = normalize(end - start)
        
        // Parameters
        let sineFrequency: Float = 3    // Number of waves
        let sineAmplitude: Float = 0.4  // Max height of wave
        let segmentCount = 200         // Smoothness
        let waveStartT: Float = 0.20      // Start wave after 25%

        for i in 0..<segmentCount {
            let t0 = Float(i) / Float(segmentCount)
            let t1 = Float(i + 1) / Float(segmentCount)
            
            var point0 = start + direction * (t0 * totalDistance)
            var point1 = start + direction * (t1 * totalDistance)
            
            if t0 > waveStartT {
                let sineProgress0 = (t0 - waveStartT) / (1.0 - waveStartT)
                let sineProgress1 = (t1 - waveStartT) / (1.0 - waveStartT)
                
                point0.y += sin(sineProgress0 * .pi * Float(sineFrequency)) * sineAmplitude * sineProgress0
                point1.y += sin(sineProgress1 * .pi * Float(sineFrequency)) * sineAmplitude * sineProgress1
            }
            
            let segmentEntity = createSegment(from: point0, to: point1)
            entity.addChild(segmentEntity)
        }
        
        return entity
    }

    private func createSegment(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Entity {
        let distance = simd_distance(start, end)
        let cylinder = ModelEntity(mesh: .generateCylinder(height: distance, radius: 0.002))
        
        cylinder.name = "Line"

        cylinder.position = (start + end) / 2
        let direction = normalize(end - start)
        cylinder.orientation = simd_quatf(from: [0,1,0], to: direction)
        cylinder.model?.materials = [SimpleMaterial(color: .white, isMetallic: false)]

        return cylinder
    }
    
    private func startTimer() {
        if timer == nil {
            timerStartDate = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in }
        }
    }

    private func pauseTimer() {
        if let startDate = timerStartDate {
            elapsedTime += Date().timeIntervalSince(startDate)
        }
        timer?.invalidate()
        timer = nil
        timerStartDate = nil
    }

}
