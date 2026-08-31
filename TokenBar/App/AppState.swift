import Foundation
import OSLog
import ServiceManagement

/// Owns everything the menu shows: provider state, refresh scheduling and
/// settings. The only `@MainActor` piece that talks to the provider layer.
@MainActor
@Observable
final class AppState {
    private(set) var states: [ProviderID: ProviderState] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    private let manager: ProviderManager
    private let settingsStore: SettingsStore
    private let snapshots: SnapshotStore
    private let history: HistoryStore
    private let notifications: NotificationManager
    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "app")

    private var autoRefreshTask: Task<Void, Never>?

    init(
        manager: ProviderManager = ProviderManager(providers: [
            ClaudeProvider(),
            CodexProvider(),
            AntigravityProvider(),
        ]),
        settingsStore: SettingsStore = SettingsStore(),
        snapshots: SnapshotStore = SnapshotStore(),
        history: HistoryStore = HistoryStore(),
        notifications: NotificationManager = NotificationManager()
    ) {
        self.manager = manager
        self.settingsStore = settingsStore
        self.snapshots = snapshots
        self.history = history
        self.notifications = notifications
    }

    // MARK: - Settings

    var settings: AppSettings {
        get { settingsStore.settings }
        set {
            let old = settingsStore.settings
            guard old != newValue else { return }
            settingsStore.settings = newValue

            if old.refreshInterval != newValue.refreshInterval {
                scheduleAutoRefresh()
            }
            if old.launchAtLogin != newValue.launchAtLogin {
                applyLaunchAtLogin(newValue.launchAtLogin)
            }
            if old.enabledProviders != newValue.enabledProviders {
                Task { await refresh() }
            }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        // Show the last known numbers immediately; the network round trip can
        // take a few seconds and an empty menu is worse than a stale one.
        let cached = await snapshots.loadAll()
        for (provider, usage) in cached where states[provider] == nil {
            states[provider] = ProviderState(usage: usage)
        }

        await notifications.requestAuthorization()
        applyLaunchAtLogin(settings.launchAtLogin)
        scheduleAutoRefresh()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let enabled = settings.enabledProviders
        for provider in ProviderID.allCases where !enabled.contains(provider) {
            states[provider] = nil
        }

        let results = await manager.refresh(enabled)

        for result in results {
            switch result {
            case .success(let usage):
                let previous = states[usage.provider]?.usage
                states[usage.provider] = ProviderState(usage: usage)
                notifications.evaluate(usage: usage, previous: previous, settings: settings)
                await snapshots.save(usage)
                // Refreshes far outnumber actual quota changes; logging only the
                // changes keeps the history useful and stops the file growing
                // by a few hundred identical rows a day.
                if previous?.limits != usage.limits {
                    await history.append(usage)
                }

            case .failure(let provider, let error):
                // Keep the last good numbers on screen alongside the error.
                states[provider] = ProviderState(usage: states[provider]?.usage, error: error)
            }
        }

        lastRefresh = Date()
    }

    private func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        guard let interval = settings.refreshInterval.duration else {
            autoRefreshTask = nil
            return
        }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Menu bar

    /// Providers in a stable display order, enabled ones only.
    var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { settings.enabledProviders.contains($0) }
    }

    /// Tightest remaining quota across everything enabled — the number that
    /// actually limits the user right now.
    var lowestRemainingPercent: Double? {
        visibleProviders
            .compactMap { states[$0]?.usage?.lowestRemainingPercent }
            .min()
    }

    var isWarning: Bool {
        guard let lowest = lowestRemainingPercent,
              let threshold = settings.warningThresholds.max()
        else { return false }
        return lowest < Double(threshold)
    }

    var menuBarTitle: String {
        switch settings.menuBarDisplay {
        case .iconOnly:
            return ""
        case .lowestRemaining:
            return Self.title(prefix: "TB", percent: lowestRemainingPercent, warning: isWarning)
        case .selectedProvider:
            let provider = settings.selectedProvider
            let percent = states[provider]?.usage?.lowestRemainingPercent
            return Self.title(prefix: provider.abbreviation, percent: percent, warning: isWarning)
        }
    }

    private static func title(prefix: String, percent: Double?, warning: Bool) -> String {
        guard let percent else { return "\(prefix) —" }
        let base = "\(prefix) \(Int(percent.rounded()))%"
        return warning ? "\(base) ⚠" : base
    }
}
