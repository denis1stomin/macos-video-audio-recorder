# RecRex — Release Notes

## Known issues

Product issues reported from real-world use, not yet fixed:

- **Large output file size.** A ~1h10m full-screen recording at the original fixed encoding settings (native display resolution, VideoToolbox's own automatic bitrate) came out to ~2.4 GB — good quality, but too big for easy sharing/storage over long sessions. **Mitigated, not yet re-verified:** the default encoding settings were tightened — resolution capped at 1080px on the longer edge, frame rate capped at 30fps, an explicit ~0.06 bits/pixel/frame video bitrate (clamped 1.5–8 Mbps), and audio switched from 128 kbps stereo to 64 kbps mono AAC (plenty for speech) — but this hasn't been validated yet against a real recording for the resulting file size/quality trade-off. Still no user-facing quality picker (e.g. High / Medium / "Optimized").
- **Black bars around shrunk video content after the captured window resizes (window-recording mode only).** Reported and reproduced: recording a specific app window, then something inside it goes fullscreen (e.g. a video player) — the encoded video keeps the dimensions locked in at recording start, so the new, differently-sized content only fills part of the frame, with the rest black. **Fixed, not yet re-verified against a real repro:** `RecordingManager` now checks each frame's real content size (via ScreenCaptureKit's per-frame `contentRect`/`contentScale` info) against the encoder's configured size; on a mismatch it pushes the new size to the live stream and rolls over to a new, correctly-sized segment (reusing the existing 1.5h segment-rollover mechanism). Whole-screen recording mode isn't affected, since a display's pixel size doesn't change mid-recording.
- **Echo when recording system audio + microphone together.** The mixed system-audio and microphone tracks produce audible echo — likely the microphone acoustically picking up the meeting app's own audio output (system audio) when not using headphones. **Next step (pending):** test whether the echo still happens with headphones on. If it disappears, it confirms acoustic feedback and the fix is acoustic echo cancellation on the microphone path — but that's real engineering work, not a quick tweak: ScreenCaptureKit's own mic capture (`SCStream` + `captureMicrophone`, what we use today) has no AEC option at all, so it'd mean switching mic capture to `AVAudioEngine` with `inputNode.setVoiceProcessingEnabled(true)`, which is known to be finicky on macOS (unpredictable channel-count changes, and can fail outright when input/output devices don't match, e.g. built-in mic + external speakers or AirPods) and would need a second capture pipeline kept in sync with the existing `SCStream`-driven `AVAssetWriter` session. If the echo persists even with headphones, AEC won't fix it — the cause would be something else (e.g. the meeting app itself duplicating audio into both the mic and system-audio streams) and needs separate investigation.

## v0.9.0-rc.2 — Release pipeline hardening (release candidate)

No functional/user-facing changes from rc.1 — this RC adds release engineering:
- GitHub Releases distribution: `.github/workflows/release.yml` builds a universal, ad-hoc-signed binary and publishes it as a GitHub Release (prerelease, since the tag has a hyphen) whenever a `v*` tag is pushed.
- CodeQL static analysis (`.github/workflows/codeql.yml`) running on every push/PR to `main` plus a weekly schedule.
- The release zip now carries a build provenance attestation (verify with `gh attestation verify`), so a downloader can confirm it was built by this repo's own public workflow from the tagged commit.

### Known limitations
Same as rc.1 below — still no notarization, no user-facing video quality settings, and not yet verified end-to-end against a real meeting or on actual CI runs.

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
