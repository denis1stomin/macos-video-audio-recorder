# RecRex — Release Notes

## v0.9.0-rc.1 — Initial scaffold (release candidate)

First working build of RecRex, a native macOS app for recording video meetings (screen, system audio, and/or microphone).

### Included
- SwiftUI app with the full three-stage window flow: choose what to record → choose a video source (whole screen or a specific app window, with live thumbnails) → recording/processing window with a live timer, pause, and stop.
- Capture engine built on ScreenCaptureKit + `AVAssetWriter`: hardware-encoded H.264/MP4 output, with system audio and microphone recorded as separate tracks alongside video.
- Long recordings automatically split into 1.5-hour segments for crash/power-loss resilience.
- Pausing stops both video and audio capture (no dead air), with a clear paused indicator and a timer that freezes accordingly.
- If the recorded window closes or its app crashes mid-recording, the app auto-stops, saves what was captured, and resets to the start screen — same as a manual Stop.
- Every completed recording is saved to Downloads with an ISO 8601 timestamped filename (Finder-style ` (2)`, ` (3)`... suffix on name collisions) and the Downloads folder opens in Finder automatically.
- Missing Screen Recording or Microphone permission shows a message pointing to System Settings, rather than failing silently.
- App Sandbox enabled, scoped to Downloads read/write and microphone access.
- Universal binary (Apple Silicon + Intel), targeting the latest macOS.
- Finalized app icon, and unit tests for the pure logic (file naming, segment scheduling, button labeling).
- GitHub Actions workflow that builds the app and runs the unit test suite on every push/PR.

### Known limitations
- Not yet distributed with a signed/notarized build — running it will trigger a Gatekeeper warning until an Apple Developer ID is added later.
- No user-facing video quality settings yet; capture uses sane hardware-encoded defaults.
- Not yet verified end-to-end against a real meeting (Zoom/Google Meet/etc.) or on GitHub Actions CI.
