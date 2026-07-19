# Askami

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://github.com/sebastianlungu/askami/actions/workflows/ci.yml/badge.svg)](https://github.com/sebastianlungu/askami/actions/workflows/ci.yml)
[![Download](https://img.shields.io/github/v/release/sebastianlungu/askami?label=Download)](https://github.com/sebastianlungu/askami/releases/latest)

**You're in a conversation. Someone says something questionable.**
⌥Z → Askami captures the last 30 seconds, figures out the answer, and speaks it back. No window. No typing. No context switching.

Askami lives in your menu bar. Press <kbd>Option</kbd>-<kbd>Z</kbd> and whatever was just said — from your mic, a meeting, a podcast, a call — is transcribed locally, reasoned over by AI, and spoken aloud as a concise answer.

---

## What it's for

| You're doing this… | …and want to | Askami handles it |
|---|---|---|
| Debating a fact with friends | "Was that really in 2019?" | Captures the last 30s, checks, speaks answer |
| On a call and someone drops a reference | "What's that company again?" | Picks it up from system audio |
| Listening to a podcast | "What did they mean by that term?" | Replays context + gives a concise explanation |
| Thinking out loud while coding | "How do I write this in SwiftUI?" | Hears your question, replies without breaking flow |

No wake word, no app switching, no typing. The entire interaction is: **press hotkey → hear answer.**

---

## How it works

1. Askami **continuously buffers** the last ~30 seconds of microphone + system audio in memory.
2. Press <kbd>⌥Z</kbd> — the buffer is sent to a local Whisper server for transcription.
3. The transcript goes to OpenCode CLI, which reasons over it via your configured LLM.
4. The answer is spoken aloud with on-device Kokoro neural TTS.

**Audio never touches disk.** Whisper and Kokoro run entirely on your Mac.

---

## Download

Grab the latest build from [Releases](https://github.com/sebastianlungu/askami/releases/latest).

**Requirements:** macOS 15+ (Apple Silicon), [OpenCode](https://opencode.ai) 1.18+, [whisper.cpp](https://github.com/ggerganov/whisper.cpp), and [espeak-ng](https://github.com/espeak-ng/espeak-ng).

```bash
# Install system deps
brew install whisper.cpp espeak-ng

# Download the Whisper model
bash scripts/setup.sh
```

Open the app, approve Microphone + System Audio when prompted, press <kbd>⌥Z</kbd>, and speak.

---

## Build from source

```bash
bash scripts/build.sh          # produces .build/askami.app
bash scripts/install.sh        # builds, signs, installs to /Applications
```

| Variable | Default | Purpose |
|---|---|---|
| `ASKAMI_MODEL_PATH` | `models/ggml-base-q5_1.bin` | Override Whisper model |
| `SIGN_IDENTITY` | `Askami Dev` | Code signing identity |
| `PATH` | system default | Tool discovery |

---

## Privacy

- Audio processed in RAM only — **never written to disk**.
- Whisper binds to `127.0.0.1` — no network audio leak.
- No telemetry, no analytics, no tracking.
- Transcripts are sent to your OpenCode provider for reasoning (configurable).
- OpenCode persists session history locally.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
