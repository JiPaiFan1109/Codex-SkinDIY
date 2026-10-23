# CodexPage 0.1.0

Windows-only derivative of the MIT-licensed Codex Dream Skin runtime. This project exposes local image/video selection as a supported flow instead of requiring edits to local configuration. It never modifies the official app package or disables its content-security policy.

Data lives under `%LOCALAPPDATA%\CodexDynamicSkin`, separate from the existing Dream Skin install. A pinned Node runtime is shipped in the Release ZIP; source builds verify the runtime before packaging. The installer copies a managed engine, takes recoverable snapshots and creates a `Codex` launcher, a background manager and a restore shortcut. Existing shortcuts must not be silently overwritten. The ChatGPT icon is copied only from a registered local official app.

The manager validates and prepares media before touching the active state. It serializes changes with the engine operation lock. Static selection must clear dynamic mode; dynamic selection must install matching media metadata. Failed processing preserves the old selection. Live application verifies the expected background and rolls back on failure. Videos use a bounded, verified local transfer to a renderer Blob; the background never receives pointer events or keyboard focus.

Warm reopening shows the existing app first, then verifies its registered package, CDP session and processes. A verified healthy session is reused. A failed candidate falls back to the full startup path. Retained hidden DOM surfaces are excluded from visible-interface verification.

The original Wallpaper Engine Earth file and private machine state are not distributed. The initial release offers a redistributable neutral demo background; users may import their own licensed Earth video. Supported codecs, file limits, dependency requirements and application-version limitations are documented explicitly.

Acceptance: automated media/rollback/renderer/launch identity tests, build/hash checks, isolated installation/shortcut validation, live compatibility evidence where it can be gathered without changing the user's working install, a clean public source repository, and a downloadable versioned Release asset.
