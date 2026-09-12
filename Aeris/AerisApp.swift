import SwiftUI
import SwiftData

@main
struct AerisApp: App {
    @State private var engine = RideEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .modelContainer(for: Ride.self)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        engine.activate()
                    }
                }
        }
    }
}
