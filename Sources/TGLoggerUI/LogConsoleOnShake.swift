import SwiftUI
import TGLogger

#if os(iOS)
import UIKit
#endif

extension View {
    /// Presents ``LogConsoleView`` when the device is shaken.
    ///
    /// Active only in **DEBUG iOS** builds. Other platforms and Release
    /// configurations return `self` unchanged, so call sites can stay
    /// unconditional. Presentation is UI-only; it never hops `MainActor`
    /// from `Logger.write`.
    ///
    /// Shake again (or Close) dismisses. Keep a menu button as well: a
    /// phone lying on a bench while talking to hardware cannot shake.
    @ViewBuilder
    public func logConsoleOnShake(
        destination: MemoryDestination,
        isEnabled: Bool = true
    ) -> some View {
        #if DEBUG && os(iOS)
        modifier(
            LogConsoleOnShakeModifier(destination: destination, isEnabled: isEnabled)
        )
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Posts ``notification`` so a custom `UIWindow` can feed the same
/// SwiftUI presenter FLEX-style (`motionEnded(.motionShake)`).
public enum LogConsoleShake {
    public static let notification = Notification.Name("TGLoggerUI.deviceDidShake")

    @MainActor
    public static func notify() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}
#endif

#if DEBUG && os(iOS)
private struct LogConsoleOnShakeModifier: ViewModifier {
    let destination: MemoryDestination
    var isEnabled: Bool
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .background {
                ShakeDetectorRepresentable()
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: LogConsoleShake.notification)) { _ in
                guard isEnabled else { return }
                isPresented.toggle()
            }
            .fullScreenCover(isPresented: $isPresented) {
                NavigationStack {
                    LogConsoleView(destination: destination)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { isPresented = false }
                            }
                        }
                }
                .background {
                    ShakeDetectorRepresentable()
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// Becomes first responder so `motionEnded(.motionShake)` is delivered
/// without subclassing the app's `UIWindow` (unlike FLEX / CocoaDebug).
private struct ShakeDetectorRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeDetectorViewController {
        ShakeDetectorViewController()
    }

    func updateUIViewController(_ uiViewController: ShakeDetectorViewController, context: Context) {}
}

private final class ShakeDetectorViewController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        resignFirstResponder()
        super.viewWillDisappear(animated)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            LogConsoleShake.notify()
        }
        super.motionEnded(motion, with: event)
    }
}
#endif
