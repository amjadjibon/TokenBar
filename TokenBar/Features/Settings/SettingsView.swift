import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        TabView {
            Form {
                Section("Providers") {
                    ForEach(ProviderID.allCases) { provider in
                        Toggle(provider.displayName, isOn: binding(for: provider))
                    }
                }

                Section("Refresh") {
                    Picker("Refresh interval", selection: $state.settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                }

                Section("Startup") {
                    Toggle("Launch TokenBar at login", isOn: $state.settings.launchAtLogin)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Display") {
                    Picker("Menu bar shows", selection: $state.settings.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    if state.settings.menuBarDisplay == .selectedProvider {
                        Picker("Provider", selection: $state.settings.selectedProvider) {
                            ForEach(ProviderID.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            Form {
                Section("Notify when remaining quota falls below") {
                    ForEach(AppSettings.availableThresholds, id: \.self) { threshold in
                        Toggle("\(threshold)%", isOn: binding(forThreshold: threshold))
                    }
                }
                Section {
                    Toggle("Notify when quota resets", isOn: $state.settings.notifyOnReset)
                } footer: {
                    Text("Reset notices are only sent for a quota you were warned about.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 460, height: 420)
    }

    private func binding(for provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { state.settings.enabledProviders.contains(provider) },
            set: { isOn in
                var settings = state.settings
                if isOn {
                    settings.enabledProviders.insert(provider)
                } else {
                    settings.enabledProviders.remove(provider)
                }
                state.settings = settings
            }
        )
    }

    private func binding(forThreshold threshold: Int) -> Binding<Bool> {
        Binding(
            get: { state.settings.warningThresholds.contains(threshold) },
            set: { isOn in
                var settings = state.settings
                if isOn {
                    settings.warningThresholds.insert(threshold)
                } else {
                    settings.warningThresholds.remove(threshold)
                }
                state.settings = settings
            }
        )
    }
}
