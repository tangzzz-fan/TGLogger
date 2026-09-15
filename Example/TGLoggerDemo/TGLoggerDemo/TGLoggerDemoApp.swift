import SwiftUI
import TGLogger

@main
struct TGLoggerDemoApp: App {
    @State private var store = DemoLogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
