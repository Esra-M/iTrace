import SwiftUI
import RealityKit
import RealityKitContent

@main
struct AppleVisionProApp: App {
    @StateObject private var appState = AppState()

    var body: some SwiftUI.Scene {
        WindowGroup(id: "main") {
            Group {
                switch appState.currentPage {
                case .content:
                    ContentView()
                case .keyboard:
                    KeyboardView()
                case .test:
                    TestView()
                case .type:
                    TypingView()
                case .click:
                    ClickingView()
                case .reach:
                    ReachView()
                case .select:
                    SelectionView()
                case .eyeTracking:
                    EyeTrackingView()
                        .frame(
                            minWidth: 1280, maxWidth: 1280,
                            minHeight: 720, maxHeight: 720)
                case .bullseyeTest:
                    BullseyeTestView()
                case .videoUpload:
                    VideoUploadView()
                }
            }
            .environmentObject(appState)
            .animation(.easeInOut, value: appState.currentPage)
        }

        ImmersiveSpace(id: "immersiveTracking") {
            ImmersiveTrackingView()
                .environmentObject(appState)
        }
        .windowStyle(.plain)
        

        ImmersiveSpace(id: "selectionObject") {
            SelectionObjectsView()
        }
        ImmersiveSpace(id: "reachObject") {
            ReachObjectView()
                .environmentObject(appState)
        }
    }
}
