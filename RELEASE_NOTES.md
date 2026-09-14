# RexGrab — Release Notes

## Known issues

Product issues reported from real-world use, not yet fixed:

- **Large output file size.** A ~1h10m full-screen recording at the original settings (native display resolution, VideoToolbox's own automatic bitrate) came out to ~2.4 GB — good quality, but too big for easy sharing/storage over long sessions. **Fixed and verified:** video is now capped at 1920px on the longer edge (real 1080p for a standard 16:9 screen — much smaller than most displays' native resolution) and 30fps, with audio at 64 kbps mono AAC. Bitrate itself is left to VideoToolbox's own content-adaptive default rather than an explicit target, which turned out to produce more reliable quality than trying to cap it ourselves. Still no user-facing quality picker (e.g. High / Medium / "Optimized").
- **Black bars around shrunk video content after the captured window resizes (window-recording mode only).** Recording a specific app window, then something inside it goes fullscreen (e.g. a video player), or the window is manually resized — the encoded video used to keep the dimensions locked in at recording start, so the new, differently-sized content only filled part of the frame, with the rest black. **Fixed, not yet re-verified:** `RecordingManager` now polls the OS every 1.5s for the recorded window's actual current size and, once a change is confirmed across a couple of polls, starts a new, correctly-sized segment instead.
- **Echo when recording system audio + microphone together.** The mixed system-audio and microphone tracks produce audible echo — likely the microphone acoustically picking up the meeting app's own audio output (system audio) when not using headphones. **Next step (pending):** test whether the echo still happens with headphones on. If it disappears, it confirms acoustic feedback and the fix is acoustic echo cancellation on the microphone path — but that's real engineering work, not a quick tweak: ScreenCaptureKit's own mic capture (`SCStream` + `captureMicrophone`, what we use today) has no AEC option at all, so it'd mean switching mic capture to `AVAudioEngine` with `inputNode.setVoiceProcessingEnabled(true)`, which is known to be finicky on macOS (unpredictable channel-count changes, and can fail outright when input/output devices don't match, e.g. built-in mic + external speakers or AirPods) and would need a second capture pipeline kept in sync with the existing `SCStream`-driven `AVAssetWriter` session. If the echo persists even with headphones, AEC won't fix it — the cause would be something else (e.g. the meeting app itself duplicating audio into both the mic and system-audio streams) and needs separate investigation.

## [v0.9.1-rc.1](https://github.com/denis1stomin/rexgrab/releases/tag/v0.9.1-rc.1) (release candidate)

RexGrab is a native macOS app for recording video meetings (screen, system audio, and/or microphone). Renamed from RecRex as of this release (bundle ID now `dev.denis1stomin.rexgrab`) — if you installed an earlier RecRex build, its Screen Recording/Microphone permissions are separate and won't carry over automatically.

### Included
- SwiftUI app with the full three-stage window flow: choose what to record → choose a video source (whole screen or a specific app window, with live thumbnails) → recording/processing window with a live timer, pause, and stop.
- Capture engine built on ScreenCaptureKit + `AVAssetWriter`: hardware-encoded H.264/MP4 output, with system audio and microphone recorded as separate tracks alongside video. Video capped at 1920px on the longer edge (true 1080p) and 30fps, with mono 64 kbps AAC audio, to keep file sizes manageable.
- Long recordings automatically split into 1.5-hour segments for crash/power-loss resilience.
- Pausing stops both video and audio capture (no dead air), with a clear paused indicator and a timer that freezes accordingly.
- If the recorded window closes or its app crashes mid-recording, the app auto-stops, saves what was captured, and resets to the start screen — same as a manual Stop.
- If a recorded app window is resized mid-recording (or its content changes size, e.g. a video going fullscreen), the encoder detects the new size and rolls over to a correctly-sized segment instead of leaving black bars. Not yet re-verified against a real repro.
- Every completed recording is saved to Downloads with an ISO 8601 timestamped filename (Finder-style ` (2)`, ` (3)`... suffix on name collisions) and the Downloads folder opens in Finder automatically.
- Missing Screen Recording or Microphone permission shows a message pointing to System Settings, rather than failing silently.
- App Sandbox enabled, scoped to Downloads read/write and microphone access.
- Universal binary (Apple Silicon + Intel), targeting the latest macOS.
- Distributed via GitHub Releases with a build provenance attestation — verify a downloaded zip was really built by this repo's public workflow with `gh attestation verify`.

### Known limitations
- Not yet distributed with a signed/notarized build — running it will trigger a Gatekeeper warning until an Apple Developer ID is added later.
- No user-facing video quality picker yet; capture uses the sane hardware-encoded defaults described above.
- The window-resize fix above hasn't been re-verified against a live repro.
- See Known issues above for the mic/system-audio echo, which is still unresolved.
