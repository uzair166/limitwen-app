import SwiftUI
import LimitwenCore

enum Design {
    static let settingsSize = CGSize(width: 460, height: 470)
    static let width: CGFloat = 386
    static let inset: CGFloat = 17
    static let warningColor = NSColor(name: "LimitwenWarning") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.94, green: 0.70, blue: 0.45, alpha: 1)
            : NSColor(srgbRed: 0.64, green: 0.36, blue: 0.15, alpha: 1)
    }
    static let warning = Color(nsColor: warningColor)
    static let secondary = Color.secondary
    static let short = Color.primary.opacity(0.76)
    static let long = Color.primary.opacity(0.46)
    static let track = Color.primary.opacity(0.09)
}

struct LimitsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredContentHeight: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your limits").font(.system(size: 16, weight: .semibold))
                    Text(model.preview ? "Preview · example values" : "A little room to think.")
                        .font(.system(size: 11)).foregroundStyle(model.preview ? Design.warning : Design.secondary)
                }
                Spacer()
                Button { Task { await model.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13)).frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless).help("Refresh limits").accessibilityLabel("Refresh limits")
                .disabled(model.preview || model.states.values.contains { $0.refreshing })
            }
            .padding(.horizontal, Design.inset).padding(.vertical, 15)
            Divider()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if model.preferences.enabled.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 25)).foregroundStyle(Design.secondary)
                            Text("Choose your subscriptions").font(.system(size: 14, weight: .medium))
                            Text("Add the tools you use in Settings.").font(.system(size: 12)).foregroundStyle(Design.secondary)
                            Button("Choose providers") { model.showSettings() }
                        }.padding(30)
                    }
                    ForEach(model.preferences.enabled) { provider in
                        ProviderSection(model: model, provider: provider)
                            .id(provider)
                        if provider != model.preferences.enabled.last { Divider() }
                    }
                    if let notice = model.notice {
                        HStack(alignment: .top, spacing: 7) {
                        Text(notice).font(.system(size: 11)).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                            .buttonStyle(.borderless).accessibilityLabel("Dismiss message")
                    }
                }
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ContentHeight.self, value: geometry.size.height)
                })
            }
            .frame(height: contentHeight)
            .onPreferenceChange(ContentHeight.self) { measuredContentHeight = $0 }
            .scrollIndicators(.automatic)
            .onChange(of: model.selected) { _, selected in
                if let selected { proxy.scrollTo(selected, anchor: .top) }
            }
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Low-limit alerts").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle("Low-limit alerts", isOn: Binding(get: { model.preferences.alertsEnabled }, set: { enabled in Task { await model.setAlerts(enabled) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .accessibilityIdentifier("low-limit-alerts")
                }
                HStack {
                    Text("When any limit reaches").font(.system(size: 11)).foregroundStyle(Design.secondary)
                    Spacer()
                    Picker("Alert threshold", selection: Binding(get: { model.preferences.threshold }, set: { value in model.change { $0.threshold = value } })) {
                        ForEach([5, 10, 20, 30, 50], id: \.self) { Text("\($0)% left").tag($0) }
                    }.labelsHidden().frame(width: 88).controlSize(.small).disabled(!model.preferences.alertsEnabled)
                }

            }.padding(.horizontal, Design.inset).padding(.vertical, 12).background(Color.primary.opacity(0.025))
            Divider()
            HStack(spacing: 8) {
                Button { model.showSettings() } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                    .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Menu {
                    Button("Refresh") { Task { await model.refresh(force: true) } }
                    Button("Cancel reset reminders") { model.cancelResetReminders() }
                        .disabled(model.preferences.resetReminders.isEmpty && model.pendingReminders.isEmpty)
                    Divider()
                    Button("Quit Limitwen") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
                } label: { Image(systemName: "ellipsis").frame(width: 18) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More options")
            }.font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(Design.secondary)
                .padding(.horizontal, Design.inset).padding(.vertical, 10)
        }
        .frame(width: Design.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private var contentHeight: CGFloat {
        let estimated = model.preferences.enabled.reduce(CGFloat(0)) { sum, provider in
            if let snapshot = model.states[provider]?.snapshot, !snapshot.windows.isEmpty {
                return sum + 60 + CGFloat(snapshot.displayWindows.count) * 68 + (model.states[provider]?.error == nil ? 0 : 40)
            }
            return sum + 125
        }
        let available = min(590, max(40, model.popoverAvailableHeight - 185))
        let initialHeight = model.preferences.enabled.isEmpty ? 180 : estimated
        return min(max(130, measuredContentHeight > 0 ? measuredContentHeight : initialHeight), available)
    }
}

private struct ContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ProviderSection: View {
    @ObservedObject var model: AppModel
    let provider: ProviderID
    private var state: ProviderState { model.states[provider] ?? ProviderState() }
    private var snapshot: UsageSnapshot? { state.snapshot }
    private var stale: Bool { snapshot?.isStale(at: model.now) == true || state.error != nil }
    private var lowWindow: QuotaWindow? {
        snapshot?.windows.first { ($0.remainingPercent ?? 101) <= Double(model.preferences.threshold) && !$0.hasElapsed(at: model.now) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: provider.symbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(provider == .claude ? Design.warning : .primary)
                    .frame(width: 26, height: 26).background(provider == .claude ? Color.orange.opacity(0.1) : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.system(size: 13, weight: .semibold))
                    if let snapshot {
                        Text((provider == .codex ? "Codex allowance · " : "") + updatedDescription(snapshot.observedAt))
                            .font(.system(size: 10.5)).foregroundStyle(Design.secondary)
                    }
                }.help(snapshot?.source ?? provider.connectionSummary)
                Spacer(minLength: 2)
                if stale { badge("Needs refresh", color: Design.secondary) }
                else if let lowWindow { badge(lowWindow.remainingPercent == 0 ? "Limit reached" : "Running low", color: Design.warning) }
                else if state.refreshing { Text("Updating…").font(.system(size: 11)).foregroundStyle(Design.secondary) }
                Button {
                    model.change { preferences in
                        if preferences.pinned.contains(provider) { preferences.pinned.removeAll { $0 == provider } }
                        else { preferences.pinned.append(provider) }
                    }
                } label: {
                    Image(systemName: model.preferences.pinned.contains(provider) ? "pin.fill" : "pin")
                        .font(.system(size: 10)).frame(width: 20, height: 24)
                }.buttonStyle(.plain)
                    .modifier(ShapedKeyboardFocus(cornerRadius: 6))
                    .foregroundStyle(Design.secondary)
                    .help(model.preferences.pinned.contains(provider) ? "Unpin from menu bar" : "Pin to menu bar")
                    .accessibilityLabel("\(model.preferences.pinned.contains(provider) ? "Unpin" : "Pin") \(provider.name)")
            }
            if let snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.displayWindows) { window in
                    QuotaRow(model: model, provider: provider, window: window, stale: stale)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyDescription).font(.system(size: 12)).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
                    if provider == .claude && !model.claudeInstalled {
                        Button("Connect Claude Code…") { model.showSettings() }.font(.system(size: 12))
                    } else {
                        Button(provider == .codex ? "Connection details…" : "Setup details…") { model.showSettings() }.font(.system(size: 12))
                        if provider == .claude { Button(provider.dashboardLabel) { openDashboard(provider) }.font(.system(size: 12)) }
                    }
                }
            }
            if let error = state.error, snapshot != nil {
                Text(error).font(.system(size: 11)).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Design.inset).padding(.vertical, 13)
        .background(model.selected == provider ? Color.primary.opacity(0.02) : Color.clear)
        .accessibilityElement(children: .contain).accessibilityLabel(provider.name)
    }
    private var emptyDescription: String {
        if let error = state.error { return error }
        if state.refreshing { return "Reading your current allowance…" }
        if provider == .claude { return model.claudeInstalled ? model.claudeAccount.missingUsageMessage : "Connect Claude Code to read your saved allowance and refresh it using your existing sign-in." }
        if provider == .codex && snapshot != nil { return "Your signed-in account hasn’t reported any subscription limits yet." }
        return "Sign in to Codex CLI to read your Codex allowance."
    }
    private func updatedDescription(_ date: Date) -> String {
        if model.preview { return "Example values" }
        guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0, date <= model.now.addingTimeInterval(60) else { return "Update time unavailable" }
        let age = max(0, Int(model.now.timeIntervalSince(date) / 60))
        if age == 0 { return "Updated just now" }
        if age < 60 { return "Updated \(age)m ago" }
        if age < 1440 { return "Updated \(age / 60)h ago" }
        return "Updated \(age / 1440)d ago"
    }
    private func badge(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct QuotaRow: View {
    @ObservedObject var model: AppModel
    let provider: ProviderID
    let window: QuotaWindow
    let stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var elapsed: Bool { window.hasElapsed(at: model.now) }
    private var low: Bool { !stale && !elapsed && (window.remainingPercent ?? 101) <= Double(model.preferences.threshold) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 12))
                Spacer()
                if let remaining = window.remainingPercent {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(remaining.rounded()))%")
                            .font(.system(size: 14, weight: .medium)).monospacedDigit().foregroundStyle(low ? Design.warning : .primary)
                        Text(stale || elapsed ? "last known" : "left").font(.system(size: 11)).foregroundStyle(Design.secondary)
                    }
                } else { Text("Not reported").font(.system(size: 11)).foregroundStyle(Design.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.track)
                    if let remaining = window.remainingPercent {
                        Capsule().fill(low ? Design.warning : window.durationMinutes == 10080 ? Design.long : Design.short)
                            .frame(width: geometry.size.width * remaining / 100).opacity(stale || elapsed ? 0.45 : 1)
                    }
                }
            }.frame(height: 4).accessibilityHidden(true)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: window.remainingPercent)
            HStack(alignment: .center, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        Text(resetText).fixedSize()
                        if let reset = window.resetsAt { Text("·"); Text(exactReset(reset)).fixedSize().monospacedDigit() }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resetText)
                        if let reset = window.resetsAt { Text(exactReset(reset)).monospacedDigit() }
                    }
                }.font(.system(size: 11)).foregroundStyle(Design.secondary)
                Spacer(minLength: 0)
                if window.resetsAt != nil && !elapsed && (!stale || model.reminderEnabled(provider, window)) {
                    Button { Task { await model.toggleReminder(provider, window) } } label: {
                        Label(model.reminderEnabled(provider, window) ? "On" : "Notify", systemImage: model.reminderEnabled(provider, window) ? "bell.badge.fill" : "bell")
                            .font(.system(size: 11)).padding(.vertical, 4)
                    }.buttonStyle(.borderless)
                        .disabled(model.pendingReminders.contains(model.reminderKey(provider, window)))
                        .foregroundStyle(model.reminderEnabled(provider, window) ? Color.green : Design.secondary)
                        .accessibilityLabel("\(model.reminderEnabled(provider, window) ? "Cancel reminder for" : "Notify when") \(provider.name) \(window.title) resets")
                }
            }
        }.accessibilityElement(children: .contain)
    }
    var resetText: String {
        ResetDescription.relative(window.resetsAt, now: model.now)
    }
    func exactReset(_ reset: Date) -> String {
        if Calendar.current.isDate(reset, inSameDayAs: model.now) { return reset.formatted(.dateTime.hour().minute()) }
        return reset.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}

@MainActor
func openDashboard(_ provider: ProviderID) {
    if let url = URL(string: provider.dashboard) { NSWorkspace.shared.open(url) }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.preview {
                    Label("Example settings", systemImage: "eye").foregroundStyle(Design.warning)
                }
                VStack(alignment: .leading, spacing: 10) {
                    heading("Menu bar")
                    Toggle("Show provider initials", isOn: Binding(
                        get: { model.preferences.showInitials },
                        set: { value in model.change { $0.showInitials = value } }))
                    Text("Inner ring: short window. Outer ring: longer window.")
                        .font(.system(size: 11)).foregroundStyle(Design.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    heading("Subscriptions")
                    ForEach(ProviderID.allCases) { provider in
                        providerControls(provider)
                        if provider != ProviderID.allCases.last { Divider() }
                    }
                    Text("Unpinned subscriptions stay in the popover. With neither pinned, one Limitwen icon remains.")
                        .font(.system(size: 11)).foregroundStyle(Design.secondary)
                }
                if let notice = model.notice {
                    Text(notice).font(.system(size: 11)).foregroundStyle(Design.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your sign-ins stay on your Mac. No analytics or copied credentials.")
                    Text("Limitwen \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                }.font(.system(size: 11)).foregroundStyle(Design.secondary)
            }
            .font(.system(size: 13))
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Design.settingsSize.width, height: Design.settingsSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }

    private func providerControls(_ provider: ProviderID) -> some View {
        let enabled = model.preferences.enabled.contains(provider)
        return VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: Binding(get: { model.preferences.enabled.contains(provider) }, set: { value in
                model.change {
                    if value { $0.enabled.append(provider) } else { $0.enabled.removeAll { $0 == provider } }
                }
                Task { await model.refresh(force: true) }
            })) {
                Label(provider.name, systemImage: provider.symbol).font(.system(size: 13, weight: .medium))
            }.toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("Enable \(provider.name)")

            Text(provider == .claude ? "Uses your Claude Code sign-in, including Team accounts." : "Uses your Codex sign-in. Shows Codex allowance.")
                .font(.system(size: 11)).foregroundStyle(Design.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Toggle("Show in menu bar", isOn: Binding(get: { model.preferences.pinned.contains(provider) }, set: { value in
                    model.change {
                        if value { $0.pinned.append(provider) } else { $0.pinned.removeAll { $0 == provider } }
                    }
                })).disabled(!enabled).accessibilityLabel("Pin \(provider.name) to menu bar")
                Spacer()
                if provider == .claude {
                    Button(model.claudeInstalled ? "Disconnect" : "Connect") {
                        if model.claudeInstalled { model.disconnectClaude() } else { model.connectClaude() }
                    }.disabled(model.preview || !enabled)
                        .accessibilityLabel(model.claudeInstalled ? "Disconnect Claude Code" : "Connect Claude Code")
                        .help("Reads saved usage and refreshes through Claude Code 2.1.273 or later. Disconnect stops reads.")
                }
            }.controlSize(.small)
            if enabled, let error = model.states[provider]?.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Design.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Keep keyboard focus visible within the control's own shape, rather than
/// stacking AppKit's rectangular halo over custom rounded selection chrome.
private struct ShapedKeyboardFocus: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(focused ? Color.primary.opacity(0.45) : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
