# justasec

Menu-bar-only macOS app: press Control-Option-Space to capture the last 30 seconds of
microphone + system audio, transcribe locally, reason via OpenCode, and speak a
concise answer aloud using local neural TTS. The app runs as a menu-bar item with
status feedback and Settings/Quit.

---

## Dependencies

| Tool | Path | Verified |
|------|------|----------|
| Swift 6.2+ | `/usr/bin/swift` | `swift --version` |
| Xcode 26.2 | `/usr/bin/xcodebuild` | `xcodebuild -version` |
| OpenCode 1.18.x | `/opt/homebrew/bin/opencode` | `opencode --version` |
| whisper-server | `/opt/homebrew/bin/whisper-server` | `whisper-server --help` (Homebrew: `brew install whisper.cpp`) |

All paths are hardcoded; the app will refuse to start if any tool is missing.

## Models

### Whisper (transcription)

**ggml-base-q5_1.bin** (multilingual, ~57 MB)

- Source: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin`
- Size: 59,707,625 bytes (verified before use)
- SHA-256: `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`
- Stored in `models/` (git-ignored)

### Kokoro-82M (text-to-speech)

**Kokoro-82M** via CoreML — ~99 MB, automatically downloaded on first use.

- Runtime: Apple Silicon (macOS 15+) via CoreML
- Source: `hexgrad/Kokoro-82M` ported by Jud [[kokoro-coreml](https://github.com/Jud/kokoro-coreml)]
- Voice: `af_heart` (American English female, fixed — no voice selector)
- Format: 24 kHz mono PCM float
- Cache location: `~/Library/Application Support/com.sebastianlungu.justasec/models/kokoro/`
- License: Apache 2.0
- Speech output uses AVAudioEngine and is not looped back through system audio (`excludesCurrentProcessAudio`)

First-use download (~99 MB) prints progress to stderr. Subsequent launches reuse the cached model — no network required.

The package's synchronous downloader cannot be interrupted mid-stream. If the speaking task is cancelled during an ongoing download, the actor returns `.cancelled` promptly. The download, already started by the package, may complete in the background and cache the model for the next launch. The driver checks task cancellation before starting the download, before constructing the engine, and resumes the actor with `.cancelled` if cancelled.

## Setup

```bash
bash scripts/setup.sh
```

Validates all four tools and downloads/verifies the model. Re-runnable.

## Build

```bash
bash scripts/build.sh
```

Produces `.build/justasec.app` — a locally signed menu-bar-only
(`LSUIElement = true`) bundle with identifier `com.sebastianlungu.justasec`.
The verified Whisper model is copied into the signed bundle so the app can be
launched from Finder or installed in `/Applications` without a working-directory dependency.
Builds use the stable `JustASec Dev` identity from the login keychain so macOS
permissions remain valid when the app is rebuilt.

## Install

```bash
bash scripts/install.sh
```

This builds, stable-signs, and installs `/Applications/justasec.app`. The first
migration from an ad-hoc or different identity resets stale TCC records and
requires one new approval. Later installs preserve the same signing requirement.

## Run

```bash
open .build/justasec.app
```

Or launch from Finder. The app lives in the menu bar with a persistent status icon.
It does not appear in the Dock or Cmd-Tab app switcher.

## Stop

- **Cmd-Q** or **Quit JustASec** from the menu-bar menu.
- Ctrl-C or `kill <PID>` (SIGTERM). The app cleans up: terminates the
whisper-server child, stops capture, stops audio, and exits.

## Permissions

First run triggers **two** system dialogs:

1. **Microphone** — required for live mic capture.
2. **Screen & System Audio Recording** — required for system audio loopback.

These are macOS TCC (Transparency, Consent, and Control) permissions keyed to
the bundle identifier and stable `JustASec Dev` signing requirement. Rebuild
with `bash scripts/install.sh` or the project `/sign` skill to preserve them.

If permission is denied, spoken error "Startup failed." is announced and the
app enters the `failed` state. To recover:

1. Quit the app.
2. Go to **System Settings → Privacy & Security → Microphone** and re-enable.
3. Go to **System Settings → Privacy & Security → Screen Recording** and
   re-enable.
4. Restart the app.

The hotkey (Control-Option-Space, or a user-configured alternative) uses the
Carbon Event Manager and does **NOT** require Accessibility permission.

## Sonic Logo

The app plays the **SNCF sonic logo** (5.04 s, 44.1 kHz stereo MP3) exactly
once on each successful pipeline invocation — after transcription and reasoning
complete, and before Kokoro TTS starts. The logo is played with an async
awaitable AVAudioPlayer that resolves only after playback finishes, adding
~5 s to end-to-end response latency.

- Error, recovery, startup, trigger-accepted, and busy-rejected paths are
  silent — no sound is emitted.
- The bundled resource at `scripts/sncf-sonic-logo.mp3` is validated by
  SHA-256 (`734c2b87…`) at build time.
- If the resource or player fails, a clear message is printed to stderr and
  the pipeline continues to TTS without interruption.

## Lifecycle States

| State | Meaning |
|-------|---------|
| `startup` | Validating deps, launching whisper-server, starting capture, registering hotkey |
| `ready` | Idle, buffering audio, waiting for hotkey |
| `processing` | Hotkey received, running pipeline (snapshot → transcribe → reason) |
| `speaking` | TTS playback active (microphone suppressed) |
| `failed` | Unrecoverable error; must be restarted |

Diagnostic messages are printed to stderr. No audio content, transcripts,
prompts, answers, or credentials are ever logged.

## Menu-Bar Status

The menu-bar icon reflects the current pipeline phase with one of seven
SF Symbol monochrome template images:

| Phase | Symbol | Accent Color | Pulse |
|-------|--------|-------------|-------|
| `launching` | hourglass | Gray | No |
| `listening` | mic.fill | Blue | No |
| `stt` | waveform | Purple | No |
| `agent` | sparkle | Orange | No |
| `success` | checkmark.circle.fill | Green | No |
| `tts` | speaker.wave.2.fill | Teal | No |
| `error` | exclamationmark.triangle.fill | Red | No |

The app also shows two disabled rows in the menu-bar menu:
**Status: <phase>** and **Shortcut: <current shortcut>** alongside the icon
and tooltip. The `listening` pulse that previously animated the Dock icon is
no longer visible; the menu-bar item renders a static icon.

## Hotkey

A standard key plus at least one modifier from Control, Option, Shift, Command.
Bare keys, modifier-only keys, Fn, and Caps Lock are rejected by the recorder.
Unsupported media keys and system-reserved combinations may pass capture in
the recorder but fail Carbon `RegisterEventHotKey`, showing an error and
preserving the previous shortcut binding.

**Control-Option-Space** (default) — triggers snapshot/transcribe/reason/speak
pipeline when in `ready` state. Pressed again during `processing` or `speaking`:
ignored (busy chime plays, no queueing).

The shortcut can be changed via the **Settings Panel**: click the menu-bar icon
and select **Settings…** to open the panel, click the shortcut button, and
press the desired combination. The shortcut is persisted in `UserDefaults` and
survives restart. If the new combination conflicts with a system shortcut or
cannot be registered, the panel shows an error and rolls back to the previous
value. The menu-bar **Shortcut** row updates immediately on success and stays
unchanged on failure or cancellation.

## Settings Panel

Click the menu-bar icon → **Settings…** to open the compact settings panel,
which contains:

- **Global Shortcut** — click to record a new hotkey combination.
- **Quit JustASec** — terminates the app gracefully.
- **Error label** — shown when shortcut registration fails.

The menu also shows a **Shortcut: <current shortcut>** row that reflects the
active hotkey. It updates immediately on success and is preserved on failure
or cancellation.

The panel does **not** require Accessibility permission (Carbon Event Manager
registers the hotkey without AX API).

## Audio Feedback

The only non-TTS audio feedback is the **SNCF sonic logo**, played once on
successful pipelines. No trigger-accepted, busy, or error sounds are played.
See [Sonic Logo](#sonic-logo) for details.

## Privacy

- **Audio is processed in RAM only.** The app never writes audio, transcripts,
  prompts, or answers to disk.
- No debug WAV files, replay files, transcript archives, or log files are
  created.
- Stage timings (e.g. `justasec: snapshot 1.234s`) are printed to stderr but
  contain no content.
- The local Whisper server binds only to `127.0.0.1` (loopback). It is not
  exposed to the LAN.
- No network telemetry, analytics, or status-item-based reporting is present.
- The app uses `NSApplication.activationPolicy = .accessory` (menu-bar app)
  with a persistent `NSStatusItem` and `LSUIElement = true`.

### Accepted Exceptions

1. **OpenCode session persistence.** OpenCode 1.18.3 persists local session
   history, including the transcript prompt and answer, in its own storage.
   justasec does not attempt to delete OpenCode's shared data. This behavior
   is accepted as a privacy exception and documented; it does not constitute a
   hidden leak.
2. **Remote provider transmission.** The transcript leaves the machine through
   the OpenCode provider model (`opencode/deepseek-v4-flash-free`). The
   provider processes the transcript to generate an answer. This is accepted
   and documented.

### Consent

Recording conversations may require the consent of all participants depending
on your jurisdiction. The user is solely responsible for obtaining consent.

## Limitations

### External-Speaker Echo

System audio plays through external speakers and leaks into the microphone.
The app merges both tracks without acoustic echo cancellation (AEC). When both
tracks contain the same audio, the transcript may include duplicated words.

**Recommendation:** use headphones for best results.

### TTS Suppression

While the app speaks an answer, microphone audio is suppressed (discarded)
during speech + a 0.5-second settling interval. This prevents the answer from
feeding back into the next capture. System audio capture continues during TTS.

The app excludes its own system audio from the capture stream
(`excludesCurrentProcessAudio`), so TTS is never looped back through the
system-audio channel — only through acoustic air leakage to the microphone.

## Text-to-Speech

Speech is generated locally using **Kokoro-82M** via
[kokoro-coreml](https://github.com/Jud/kokoro-coreml) (v0.11.2, Apache 2.0).

- **Voice**: `af_heart` (American English female, hardcoded — no selector).
- **Model download**: automatic on first use, cached at `~/Library/Application Support/com.sebastianlungu.justasec/models/kokoro/` (~99 MB). Reusable offline after first download.
- **Playback**: synthesized audio is streamed through `AVAudioEngine` / `AVAudioPlayerNode` at 24 kHz. Playback starts as soon as the first chunk is synthesized.
- **Concurrency**: one utterance at a time; concurrent speak requests return `.failed`. A 30-second timeout per utterance guards against hangs; the timeout returns `.failed`.
- **Error handling**: model download/inference failures print to stderr and return `.failed`. The orchestrator recovers by speaking a fallback message.
- **Language**: English only (kokoro-coreml includes an English G2P pipeline). The `language` parameter in the speech protocol is accepted but ignored.
- **No system-voice fallback**: AVSpeechSynthesizer is not used.
- **Compute**: CoreML inference runs on **CPU only** (`forceCPU: true`). On this hardware the ANE/E5RT accelerator emits a non-fatal shape-inference fallback (`"Failed to PropagateInputTensorShapes"`) while still producing correct audio on GPU; local probes confirmed CPU output is byte-identical and synthetically faster (RTF ~0.7× on M1 Pro) than the GPU path, with no fallback noise. This is an intentional policy, not a workaround — CPU inference is more predictable for a background menu-bar app.

### Model Substitution (NOT SUPPORTED)

The `JUSTASEC_MODEL_PATH` environment variable exists and changes where the
app looks for the model file at runtime. However, `WhisperServerConfig.validateModel()`
enforces the exact file size (59,707,625 bytes) and SHA-256 hash of
`ggml-base-q5_1.bin` before launch. A larger model such as `large-v3-turbo`
would fail validation at startup.

To enable a larger model the validation logic in `WhisperServerConfig.validateModel()`
(`Sources/justasec/WhisperTranscriptionTypes.swift:79`) would need to be
relaxed or made conditional. This is an accepted gap; the validation hash is
hardcoded for v0 safety.

### Known Technical Debt

The following issues are documented in `docs/hoff/debt/`:

- **`LifecycleStateMachine`** is `@unchecked Sendable` rather than an actor,
  and there is no cross-process lock to prevent concurrent app instances.
  (Commit pending — strict concurrency/function-size gates now green.)
- **OpenCode tool escalation protection** relies on the `OPENCODE_PERMISSION`
  environment variable — an undocumented OpenCode feature that may change. The
  `--pure` flag only disables external plugins, not built-in tools.
  **OpenCode child environment is allowlisted**: only runtime essentials (`HOME`,
  `PATH`, `TMPDIR`, `LANG`/`LC_*`, `XDG_*`) and known provider credential key
  name prefixes (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `AWS_*`, `BEDROCK_*`,
  `AZURE_OPENAI_*`, `VERTEX_AI_*`, etc.) are forwarded. `DYLD_*`, `LD_*`,
  `BASH_FUNC_*`, and arbitrary keys are excluded. `OPENCODE_PERMISSION` is
  force-set to deny-all after filtering. The child also inherits network
  entitlements and can access the local Whisper endpoint.
- **SIG_IGN is inherited by Process children on macOS** — the app sets
  `SIG_IGN` for `SIGINT`/`SIGTERM`, and `whisper-server` (launched via
  `Process`) inherits this disposition. Consequently `proc.interrupt()` and
  `proc.terminate()` may have no effect on the child. The termination
  escalation short-circuits to `SIGKILL` after brief 0.5s waits per signal;
  direct PID `SIGKILL` is the only guaranteed termination path on this host.
- **Startup ordering** transitions to `ready` after hotkey registration but
  before capture callbacks have necessarily delivered the first audio samples.
  A trigger during this window may produce "no capture time."
- **20-second hotkey-to-speech latency target** has not been benchmarked.
- **TCC permissions** must be manually approved in System Settings; automated
  reset recovery and permission re-acquisition are out of scope.
- **ScreenCaptureKit capture exhaustion and recovery** after repeated
  start/stop cycles is not production-ready.

### Out of Scope (Not Implemented)

- Configurable lookback duration (fixed at 30 seconds).
- Continuous transcription or automatic unsolicited answers.
- Launch at login, system LaunchDaemon, installer, notarization, App Store
  distribution, or production code signing.
- Windows, Linux, Intel Mac, iOS, or remote deployment.
- OBS, virtual audio drivers, Python, Faster-Whisper, Rust, llama.cpp, or any
  local reasoning LLM outside OpenCode.
- Audio archives, transcript history, replay playback, diarization, speaker
  identification, or AEC.
- Production-grade recovery across sleep/wake, AirPlay, protected-media,
  Bluetooth, and device-routing changes.

## Troubleshooting

### Startup fails: "dependency validation failed"

Run `bash scripts/setup.sh` to verify all four tools are installed and
reachable at their expected paths. If `whisper-server` is missing: `brew install whisper.cpp`.

### Startup fails: "Whisper server not ready"

Port 19990 may be occupied. Kill any existing `whisper-server` process and
restart. The server binds only to loopback and must be reachable at the
default port (hardcoded in `WhisperTranscriber` and `WhisperServerConfig`).

### Startup fails: model validation error

The model file at `models/ggml-base-q5_1.bin` is missing, wrong size, or has
a wrong SHA-256. Re-run `bash scripts/setup.sh` to re-download and verify.

### Microphone permission denied

Quit the app, re-enable in System Settings → Privacy & Security →
Microphone, restart.

### Screen Recording permission denied

Quit the app, re-enable in System Settings → Privacy & Security →
Screen Recording, restart.

### OpenCode not responding

Port 19990 is for Whisper, not OpenCode. OpenCode is invoked as a child
process (`opencode run --pure --model opencode/deepseek-v4-flash-free`).
Check that:
- `opencode` is at `/opt/homebrew/bin/opencode`.
- The model `opencode/deepseek-v4-flash-free` is available (`opencode models`).
- The `OPENCODE_PERMISSION` environment variable is not overridden in your
  shell (the app sets its own deny-all value).

### Hotkey does nothing

The app may still be in `startup` or `failed` state. Check stderr output.
Only `ready` state accepts triggers.

## Latency

The acceptance target is spoken output within **~20 seconds** of the hotkey
(after model warm-up) on M1 Pro / 32 GB. Stage timings are printed to stderr:

```
justasec: snapshot 1.234s
justasec: transcription 3.456s
justasec: opencode 5.678s
justasec: time-to-speech 10.368s
```

The SNCF sonic logo adds ~5.04 s (full MP3 duration) to the time-to-speech
latency. These are rough guidelines — actual latency depends on audio length,
Whisper model (Base Q5), OpenCode provider availability, and system load.

## Project Structure

```
justasec/
├── Package.swift              # SwiftPM executable + test target; depends on kokoro-coreml v0.11.2
├── Package.resolved           # Dependency lockfile (reproducible builds)
├── justasec.entitlements      # Sandbox entitlements (mic, network, loopback)
├── scripts/
│   ├── setup.sh               # Validate deps + download model
│   ├── build.sh               # Release build + app bundle + stable sign
│   ├── install.sh             # Identity-aware install + TCC migration
│   ├── Info.plist             # Bundle metadata (LSUIElement: true, usage descriptions)
│   ├── AppIcon.icns           # Custom app icon
│   ├── generate-icon.sh       # Icon generation helper
│   ├── generate_icon.swift    # Icon generation source
│   └── sncf-sonic-logo.mp3    # SNCF sonic logo (5.04 s, 44.1 kHz stereo, validated at build)
├── models/
│   ├── .gitkeep
│   └── ggml-base-q5_1.bin     # (git-ignored) Whisper model weights
├── Sources/justasec/          # 30 source files, menu-bar-only with settings panel
├── Tests/justasecTests/       # 13 test files, ~400+ tests
└── docs/hoff/debt/            # Known debt artifacts
```
