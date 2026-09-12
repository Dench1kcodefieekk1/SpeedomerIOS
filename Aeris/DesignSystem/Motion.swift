import SwiftUI
import UIKit

extension Animation {
    /// House motion for ride state transitions. Returns `nil` under Reduce
    /// Motion so every animation site degrades to an instant change.
    static func glass(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.4)
    }
}

@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
