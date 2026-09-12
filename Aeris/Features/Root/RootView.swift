import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case ride, map, history, settings
    }

    @State private var selection: Tab = .ride

    var body: some View {
        TabView(selection: $selection) {
            SpeedometerView()
                .tabItem { Label("Ride", systemImage: "speedometer") }
                .tag(Tab.ride)

            RideMapView(onOpenHistory: { selection = .history })
                .tabItem { Label("Map", systemImage: "map") }
                .tag(Tab.map)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .minimizeTabBarOnScrollIfAvailable()
    }
}

private extension View {
    /// iOS 26 minimizes the Liquid Glass tab bar while scrolling lists.
    @ViewBuilder
    func minimizeTabBarOnScrollIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
