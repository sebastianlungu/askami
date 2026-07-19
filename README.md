# askami

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Menu-bar-only macOS app: press <kbd>Control</kbd>-<kbd>Option</kbd>-<kbd>Space</kbd> to capture the last 30 seconds of microphone + system audio, transcribe locally via Whisper, reason via OpenCode CLI, and speak a concise answer aloud using Kokoro neural TTS.

## Requirements

- macOS 15+ (Apple Silicon)
- Swift 6.2+, Xcode 26.2
- [OpenCode](https://opencode.ai) 1.18+ (`/opt/homebrew/bin/opencode`)
- [whisper-server](https://github.com/ggerganov/whisper.cpp) (`brew install whisper.cpp`)
- [espeak-ng](https://github.com/espeak-ng/espeak-ng) (`brew install espeak-ng`)

Tool paths may be overridden via `PATH` — see [Configuration](#configuration).

## Quick Start

```bash
# Validate dependencies and download the Whisper model
bash scripts/setup.sh

# Build and install
bash scripts/build.sh        # produces .build/askami.app
bash scripts/install.sh      # builds, signs, and installs to /Applications

# Launch
open .build/askami.app
```

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `ASKAMI_MODEL_PATH` | `models/ggml-base-q5_1.bin` | Override Whisper model path |
| `SIGN_IDENTITY` | `Askami Dev` | Code signing identity |
| `PATH` | system default | Tool discovery for swift, opencode, whisper-server, espeak-ng |

## Permissions

First launch triggers Microphone and Screen & System Audio Recording dialogs.
The hotkey does **not** require Accessibility permission (uses Carbon Event Manager).

## Privacy

- Audio is processed in RAM only — never written to disk.
- Whisper server binds to `127.0.0.1` only.
- No telemetry, analytics, or network reporting.
- OpenCode persists session history locally (accepted exception).
- Transcripts are sent to the configured OpenCode provider for reasoning.

## Project

```
askami/
├── Package.swift
├── Package.resolved
├── askami.entitlements
├── scripts/
│   ├── build.sh
│   ├── install.sh
│   ├── setup.sh
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── ready-chime.mp3
├── models/
│   └── .gitkeep
├── Sources/askami/
└── Tests/askamiTests/
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

Apache 2.0 — see [LICENSE](LICENSE).
