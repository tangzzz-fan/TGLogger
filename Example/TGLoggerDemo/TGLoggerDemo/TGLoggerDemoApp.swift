import SwiftUI
import TGLogger
import TGLoggerUI
#if os(iOS)
import UIKit
#endif

@main
struct TGLoggerDemoApp: App {
    @State private var store = DemoLogStore()

    init() {
        #if DEBUG && os(iOS)
        // Shake-to-undo would consume the motion before the console detector.
        UIApplication.shared.applicationSupportsShakeToEdit = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .logConsoleOnShake(destination: store.memory)
        }
    }
}
