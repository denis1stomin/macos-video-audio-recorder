# 🦖 RexGrab

**A native macOS app for recording your screen, system audio, and microphone — built for capturing video meetings, demos, and tutorials without any third-party service in the loop.**

[![Build and Test](https://github.com/denis1stomin/rexgrab/actions/workflows/build.yml/badge.svg)](https://github.com/denis1stomin/rexgrab/actions/workflows/build.yml)
[![CodeQL](https://github.com/denis1stomin/rexgrab/actions/workflows/codeql.yml/badge.svg)](https://github.com/denis1stomin/rexgrab/actions/workflows/codeql.yml)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AVFoundation-orange)](https://developer.apple.com/swift/)

RexGrab records your Zoom, Google Meet, or Microsoft Teams calls (or literally anything else on your screen) straight to a local MP4 — no browser extension, no cloud upload, no subscription. Just a small native app built on Apple's own [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) and `AVAssetWriter`.

---

## Why RexGrab?

Most screen recorders either bury the feature inside a bloated all-in-one app, require a paid tier for local-only recording, or ship as a browser extension with no real access to system audio. RexGrab does one thing: record your screen and/or audio, save it to Downloads, done.

- **Fully local** — nothing leaves your Mac. No accounts, no cloud storage, no telemetry.
- **Native and lightweight** — SwiftUI + ScreenCaptureKit + hardware-accelerated H.264 encoding via VideoToolbox, not an Electron wrapper.
- **Separate audio tracks** — system audio and microphone are recorded as independent tracks in the output file, so you (or your editor) can mute/adjust each independently in post.
- **Two clicks to start recording.** That's the whole point.

## Features

- 🎥 **Record video** — whole screen or a specific app window, with a live thumbnail picker for each.
- 🔊 **Record system audio** — scoped to a single app when recording its window, or all system sound when recording the whole screen. Always excludes RexGrab's own audio.
- 🎙️ **Record microphone** — mixed in as a separate track, on its own or alongside system audio.
- ⏸️ **Pause / resume** — cleanly stops both video and audio (no dead air, no frozen frame) and resumes on demand.
- 🛡️ **Crash-resilient** — long recordings automatically roll over into new 1.5-hour segments, so a crash or power loss doesn't corrupt hours of footage.
- 🪟 **Auto-stop on window close** — if you're recording a specific app window and it closes or crashes, RexGrab saves what it captured and resets, just like hitting Stop.
- 📐 **Adapts to window resizes** — if you're recording a specific app window and it resizes mid-recording (e.g. something inside it goes fullscreen, or you manually resize it), RexGrab detects the change and starts a new, correctly-sized segment instead of leaving black bars around the shrunk or repositioned content.
- 📁 **Just works with Finder** — every finished recording is saved to `~/Downloads` with a clean, sortable timestamped filename, and the folder opens automatically when you're done.
- 🔒 **Sandboxed** — RexGrab runs inside the macOS App Sandbox, scoped only to Downloads access and microphone input.

## How it works

1. **Choose what to record** — toggle video, system audio, and/or microphone.
2. **Pick a source** (if recording video) — whole screen or a specific app window, each with live previews.
3. **Hit record** — the app window hides; macOS's own recording indicator confirms capture is live.
4. **Click the Dock icon anytime** to bring up the live timer with Pause/Stop controls.
5. **Stop** — your file lands in Downloads, which opens automatically in Finder.

## Requirements

- macOS with current [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)/AVFoundation support (targets the latest macOS SDK)
- Screen Recording and (if used) Microphone permission, granted via System Settings → Privacy & Security — RexGrab will tell you exactly what's missing if a permission isn't granted

## Download

Prebuilt universal binaries (Apple Silicon + Intel) are published on the [Releases](https://github.com/denis1stomin/rexgrab/releases) page. RexGrab isn't signed with an Apple Developer ID yet (see [`CLAUDE.md`](CLAUDE.md) for why), so Gatekeeper will block the unzipped app on first launch — right-click `RexGrab.app` → **Open** → **Open** to run it anyway; you only need to do this once.

Each release zip carries a [build provenance attestation](https://docs.github.com/en/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds), proving it was built by this repo's public `release.yml` workflow from the tagged source — not a substitute for Apple notarization's malware scan, but it lets you confirm the download wasn't tampered with in transit. Verify it with the [GitHub CLI](https://cli.github.com/) (adjust the filename to match whichever release you downloaded):

```sh
gh attestation verify RexGrab-vX.Y.Z-macOS.zip --repo denis1stomin/rexgrab
```

## Building from source

Prefer to build it yourself instead:

```sh
git clone git@github.com:denis1stomin/rexgrab.git
cd rexgrab
make run
```

Or open `RexGrab.xcodeproj` directly in Xcode 26+ and hit Run. Other useful targets:

```sh
make build   # build only
make test    # run the unit test suite
make clean   # remove build artifacts
```

## Output format

- **Container:** MP4
- **Video:** H.264, hardware-encoded, capped at 1920px on the longer edge (real 1080p for a standard 16:9 screen) and 30fps, bitrate left to VideoToolbox's own content-adaptive default
- **Audio:** system audio and microphone as separate mono AAC tracks (when both are enabled), 64 kbps each — plenty for speech
- **Filename:** `Recording YYYY-MM-DDTHH-MM-SS.mp4`, saved to `~/Downloads`

## Project status

RexGrab is under active development... okay, not really — it's a solo weekend project, and once it reliably does what I need, active development mostly stops. The core recording flow works end-to-end; distribution (signed builds via GitHub Releases) and broader real-world testing are still in progress. See [`RELEASE_NOTES.md`](RELEASE_NOTES.md) for what's shipped and known limitations, and [`CLAUDE.md`](CLAUDE.md) for the full architecture and decision log.

Bug reports and feature requests are still very welcome, though — I just can't promise a release schedule.

## Contributing

Issues and pull requests are welcome. The project's architectural decisions and open questions are tracked in [`CLAUDE.md`](CLAUDE.md) — worth a skim before proposing a significant change.

## License

[MIT](LICENSE) © Denis Istomin
