import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("speedUnit") private var unitRaw = SpeedUnit.kilometersPerHour.rawValue
    @AppStorage("keepScreenOn") private var keepScreenOn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Speed & Distance", selection: $unitRaw) {
                        Text("Kilometers (km/h)").tag(SpeedUnit.kilometersPerHour.rawValue)
                        Text("Miles (mph)").tag(SpeedUnit.milesPerHour.rawValue)
                    }
                }

                Section {
                    Toggle("Keep Screen On While Riding", isOn: $keepScreenOn)
                } footer: {
                    Text("Prevents the display from sleeping so you can glance at your speed while riding.")
                }

                Section("About") {
                    LabeledContent("Aeris", value: versionString)
                    LabeledContent("Designed for", value: "iOS 26 • Liquid Glass")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: keepScreenOn) { _, enabled in
                UIApplication.shared.isIdleTimerDisabled = enabled
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            }
        }
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
