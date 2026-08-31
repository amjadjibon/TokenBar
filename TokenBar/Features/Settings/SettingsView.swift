import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        TabView {
            Form {
                Section {
                    ForEach(ProviderID.allCases) { provider in
                        HStack {
                            Toggle(provider.displayName, isOn: binding(for: provider))
                            Spacer(minLength: 12)
                            // A TextField's title renders as a leading label on
                            // macOS, so the reported plan goes in `prompt` to sit
                            // inside the field as placeholder text instead.
                            TextField(
                                "",
                                text: planBinding(for: provider),
                                prompt: Text(planPlaceholder(for: provider))
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .accessibilityLabel("\(provider.displayName) plan label")
                        }
                    }
                } header: {
                    Text("Providers")
                } footer: {
                    Text("A plan you type here is shown as the badge beside that provider. Leave it empty to use whatever the provider reports — Antigravity reports none.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    /// Shows the reported plan as the placeholder, so it is clear what the field
    /// overrides and what appears if it is left empty.
    private func planPlaceholder(for provider: ProviderID) -> String {
        state.states[provider]?.usage?.plan ?? "Plan"
    }

    private func planBinding(for provider: ProviderID) -> Binding<String> {
        Binding(
            get: { state.settings.planLabels[provider] ?? "" },
            set: { newValue in
                var settings = state.settings
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    settings.planLabels.removeValue(forKey: provider)
                } else {
                    // Stored unmodified so spaces can be typed mid-word.
                    settings.planLabels[provider] = newValue
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
