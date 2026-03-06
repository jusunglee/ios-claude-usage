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

            VStack(alignment: .leading, spacing: 8) {
                Text("How to get your session key:")
                    .font(.subheadline.bold())
                instructionRow(number: "1", text: "Open claude.ai in your browser and log in")
                instructionRow(number: "2", text: "Open DevTools (⌘⌥I)")
                instructionRow(number: "3", text: "Go to Application → Cookies → claude.ai")
                instructionRow(number: "4", text: "Copy the value of sessionKey")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            TextField("sk-ant-sid01-...", text: $sessionKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            Button("Save & Connect") {
                guard !sessionKey.isEmpty else { return }
                let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let saved = KeychainHelper.saveSessionKey(trimmed)
                print("[DEBUG] Save result: \(saved), key length: \(trimmed.count)")
                if saved {
                    hasKey = true
                    sessionKey = ""
                    refresh()
                } else {
                    error = "Failed to save session key to Keychain"
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
                    if let sonnet = usage.sonnetWeekly {
                        UsageCard(title: "Sonnet Weekly", subtitle: "7-day Sonnet limit", window: sonnet)
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

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 18, height: 18)
                .background(.blue.opacity(0.2), in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
