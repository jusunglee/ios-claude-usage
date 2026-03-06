import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var sessionKey = ""
    @State private var hasKey = false
    @State private var usage: UsageData?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if hasKey {
                    usageView
                } else {
                    setupView
                }
            }
            .navigationTitle("Claude Usage")
        }
        .onAppear {
            hasKey = KeychainHelper.loadSessionKey() != nil
            if hasKey {
                usage = UsageService.cachedUsage()
                refresh()
            }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Claude Usage Widget")
                .font(.title2.bold())

            Text("Paste your sessionKey cookie from claude.ai to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            TextField("sk-ant-sid01-...", text: $sessionKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            Button("Save & Connect") {
                guard !sessionKey.isEmpty else { return }
                if KeychainHelper.saveSessionKey(sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    hasKey = true
                    sessionKey = ""
                    refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sessionKey.isEmpty)

            Spacer()
        }
    }

    // MARK: - Usage Display

    private var usageView: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let usage {
                    UsageCard(title: "Session Window", subtitle: "5-hour rolling", window: usage.sessionWindow)
                    UsageCard(title: "Weekly Usage", subtitle: "7-day limit", window: usage.weeklyUsage)
                    if let opus = usage.opusWeekly {
                        UsageCard(title: "Opus Weekly", subtitle: "7-day Opus limit", window: opus)
                    }

                    Text("Updated \(usage.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isLoading {
                    ProgressView("Loading usage...")
                        .padding(.top, 60)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { refresh() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .refreshable { await fetchUsage() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        signOut()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        Task { await fetchUsage() }
    }

    private func fetchUsage() async {
        isLoading = true
        error = nil
        do {
            usage = try await UsageService.fetchUsage()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func signOut() {
        _ = KeychainHelper.deleteSessionKey()
        UsageService.clearCache()
        usage = nil
        hasKey = false
    }
}

// MARK: - Usage Card

struct UsageCard: View {
    let title: String
    let subtitle: String
    let window: UsageWindow

    private var color: Color {
        switch window.utilizationPercent {
        case ..<50: return .green
        case ..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let reset = window.timeUntilReset {
                    Text("Resets in \(reset)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: window.utilizationPercent, total: 100)
                .tint(color)

            Text("\(Int(window.utilizationPercent))%")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(color)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
