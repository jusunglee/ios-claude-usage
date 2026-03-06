# Claude Usage Widget - iOS

## Overview
iOS app + WidgetKit extension that shows Claude Pro/Team usage limits. Uses session key auth against claude.ai internal API.

## Architecture
- `Shared/` — code compiled into both app and widget extension targets
- `ClaudeUsage/` — main iOS app (SwiftUI)
- `ClaudeUsageWidget/` — WidgetKit extension
- Data sharing: App Groups (`group.com.juicebox.claudeusage`) for UserDefaults, Keychain with shared access group
- Project generated via XcodeGen (`project.yml`)

## API
- `GET https://claude.ai/api/organizations` — returns org list, we take the first UUID
- `GET https://claude.ai/api/organizations/{org_id}/usage` — returns session/weekly/opus usage percentages
- Auth: `Cookie: sessionKey=<key>` header

## Key decisions
- iOS 17+ minimum (modern WidgetKit APIs)
- StaticConfiguration (no user-configurable widget intents)
- 15-minute widget refresh interval
- Session key stored in Keychain with shared access group
- Cached usage in App Group UserDefaults so widget can read even if fetch fails
