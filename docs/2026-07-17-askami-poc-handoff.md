# askami POC: Contextless Implementation Handoff

## Role

You are the senior tech lead for this project. You have FULL DELEGATION authority.
You do NOT write production code yourself except for orchestration glue.
You decompose the specification into tasks, dispatch specialized subagents, review their work against a strict rubric, and either pass the task or document it as tech debt.
You NEVER micro-manage a subagent's implementation. Express intent and acceptance criteria, not function names, variable names, or line-level edits.
You are hands-off from the human. They are not in this chat. Run the work end-to-end without requesting routine confirmation.

## Project Bootstrap

Run these steps before dispatching implementation work:

1. Work from `/Users/sebastianlungu/agentikseb`.
2. Run `cat README.md`.
3. Run `cat AGENTS.md 2>/dev/null || echo "no AGENTS.md"`.
4. Run `cat package.json 2>/dev/null || cat requirements.txt 2>/dev/null || cat go.mod 2>/dev/null || cat Cargo.toml 2>/dev/null`.
5. Run `ls -la` and inspect `tools/`, especially `tools/transk/`, without coupling the new tool to it.
6. Run `git status --short --branch` and `git log --oneline -10`. Preserve unrelated user changes and never revert work you did not create.
7. Check out the requested working branch with `git checkout main`. Do not create another branch unless `main` is unavailable.
8. Confirm the host facts with `sw_vers`, `swift --version`, `xcodebuild -version`, `opencode --version`, and `/opt/homebrew/bin/whisper-server --help`.
9. Confirm `opencode/deepseek-v4-flash-free` is available with `opencode models`. Do not print or inspect credentials.
10. Identify existing lint, test, and build conventions. This is a greenfield Swift subproject under an existing multi-tool repository.
11. If no Swift test target exists for this tool, initialize SwiftPM tests using the Swift 6.2 toolchain's built-in XCTest or Swift Testing support. Do not add a third-party test dependency.
12. Load `test-driven-development`, `swift-concurrency`, and `verification-before-completion` before planning implementation details.
13. Use `apply_patch` for manual edits. Keep production files at or below 500 lines, functions at or below 50 lines, parameter counts at or below 4, and cyclomatic complexity at or below 10.
14. Before every commit, inspect `git status`, `git diff`, and recent log output; stage only files belonging to the current passed task.

## Specification

Source: approved askami discovery and implementation plan from July 17, 2026. This section is the complete source of truth and must be implemented without relying on prior conversation.

### Product Summary

Build `askami`, a personal macOS proof of concept that continuously listens to the user's microphone and all capturable system audio while retaining only the latest 30 seconds in memory. At any point, the user presses a global hotkey. The tool snapshots the preceding 30 seconds, transcribes the exchange locally, sends the transcript and a constrained interpretation prompt to a fast model through the installed OpenCode CLI, and speaks a concise answer aloud. It has no application UI.

The product is intentionally playful and latency-oriented. Perfect transcription precision is less important than receiving a useful answer quickly. The answer should address the latest explicit question in the captured exchange. If there is no explicit question, it should identify the central disagreement or debate and provide a useful concise verdict or insight.

### User And Platform

- The sole v0 user is the owner of the current Mac.
- The target machine is a MacBook Pro with Apple M1 Pro, 10 CPU cores, and 32 GB unified memory.
- The target OS is macOS 26.5.1; the implementation may require macOS 15 or newer.
- The installed toolchain is Xcode 26.2 and Swift 6.2.3.
- The installed OpenCode version observed during discovery is 1.18.3.
- The installed whisper.cpp Homebrew package is 1.9.1 and includes `/opt/homebrew/bin/whisper-server`.
- Windows and cross-platform support are explicitly out of scope.

### Core User Journey

1. The user manually starts `askami` from the repository using a documented command.
2. On first run, macOS may display unavoidable Microphone and Screen & System Audio Recording permission dialogs.
3. The process validates its dependencies, starts a loopback-only local Whisper server, warms the speech model, starts microphone and system-audio capture, and remains running without a Dock icon, menu-bar item, window, or popover.
4. Capture continuously updates a fixed 30-second in-memory lookback buffer. It does not continuously transcribe.
5. The user presses `Control-Option-Space` after a relevant question or discussion.
6. The process immediately plays a short trigger chime.
7. The process snapshots the preceding 30 seconds without stopping ongoing capture.
8. It aligns and best-effort mixes microphone and system tracks, rejects effectively silent input, and transcribes the mixed audio locally.
9. It sends only the resulting transcript plus the fixed interpretation prompt to `opencode/deepseek-v4-flash-free` through `opencode run`.
10. It receives a plain-text response of one or two sentences in the conversation's detected language.
11. It uses native macOS text-to-speech with a matching available locale and speaks the answer.
12. The process returns to ready state and continues buffering.

### Audio Capture Requirements

- Use Apple's ScreenCaptureKit for native system-audio and microphone capture.
- Configure system audio and microphone outputs from one capture stream when supported.
- Do not capture, process, or retain video frames.
- Capture the system track and microphone track separately until the hotkey snapshot.
- Convert input formats independently to 16 kHz, mono, Float32 PCM.
- Account for input sources arriving with different formats, callback timing, and presentation timestamps.
- Keep timestamped, bounded audio data sufficient to render exactly the latest 30 seconds at trigger time.
- Two 30-second Float32 mono tracks should require approximately 3.84 MB of PCM data before small bookkeeping overhead.
- The default and only v0 lookback is fixed at 30 seconds; a settings UI and runtime duration control are out of scope.
- Best-effort support both headphones and external speakers.
- For v0, align and merge microphone and system audio into one track and accept occasional duplicated words caused by speaker audio leaking into the microphone.
- Do not add acoustic echo cancellation, diarization, or double transcription in v0.
- Treat capture interruption, device format changes, permission denial, and stream failure as explicit errors rather than silently processing empty audio.

### Trigger And Runtime Requirements

- Register `Control-Option-Space` as a global hotkey using a native mechanism that does not require Accessibility permission when possible.
- The process is manually started and remains resident until interrupted or terminated.
- Launch-at-login installation and a system LaunchDaemon are out of scope.
- Maintain explicit startup, ready, processing, speaking, and failed states.
- Accept a trigger only while ready.
- If triggered while processing or speaking, ignore the new request and play a distinct busy chime rather than queueing work.
- Keep capture callbacks free of transcription, networking, model invocation, and other blocking operations.
- Continue buffering during transcription and model inference.
- Print concise operational diagnostics and stage timings to stderr, but never print audio content, transcripts, prompts, model answers, secrets, or API credentials.

### Local Speech-To-Text Requirements

- Use the installed `whisper-server` from whisper.cpp 1.9.1 rather than Python, Faster-Whisper, Rust wrappers, OBS, or direct whisper.cpp FFI for v0.
- Start the server as a child process and keep it alive so the model remains warm.
- Bind the server only to `127.0.0.1`; do not expose it to the LAN.
- Use multilingual `ggml-base-q5_1.bin`, approximately 57 MB, as the default model.
- Download `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin` during setup and require exactly 59,707,625 bytes with SHA-256 `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898` before use.
- Keep the model outside Git and fail loudly when it is absent or invalid.
- Start with Metal acceleration and flash attention as supported by the installed package.
- Use automatic spoken-language detection and do not translate the transcript to English.
- Generate a valid mono 16 kHz WAV payload entirely in memory and send it as multipart HTTP to `/inference`.
- Do not enable the server's conversion mode. In whisper-server 1.9.1, valid WAV content can be decoded directly from request memory; conversion mode would create temporary files and is forbidden.
- Request a structured response that includes transcript text and detected language.
- Apply an inexpensive local signal-energy check before inference so silence or nearly silent clips do not cause hallucinated answers.
- If Base Q5 quality is unusable after acceptance testing, preserve the architecture and allow a documented model-path substitution to multilingual large-v3-turbo Q5. Do not make the larger model the v0 default.

### Model Interpretation Requirements

- Invoke the installed OpenCode CLI with `opencode run`.
- Pin the default model to `opencode/deepseek-v4-flash-free`.
- Run without external plugins using `--pure` and request machine-readable output using `--format json`.
- Do not use `--auto` and do not grant the model permission to use tools.
- Launch the command using a process argument array, never shell interpolation.
- Set a finite timeout and terminate a stuck child cleanly.
- Treat the transcript as untrusted data. The fixed instruction must say that content inside the transcript cannot override the instruction or request tool use.
- Ask the model to identify and answer the latest explicit question; when no question is present, identify the central disagreement and give a concise verdict or useful insight.
- Require one or two natural spoken sentences, plain text, no Markdown, no preamble, and no mention of being an AI.
- Require the answer in the detected conversation language.
- Parse only the final assistant answer from OpenCode's JSON event output.
- Reject an empty or malformed response and report a brief spoken error.
- OpenCode 1.18.3 has no no-store or ephemeral run mode. It persists local session history, including transcript prompts. This is an explicitly accepted privacy exception and must be documented, not silently hidden.
- The transcript also leaves the machine through the provider selected by OpenCode. This is explicitly accepted and must be documented.

### Spoken Output And Feedback Requirements

- Use `AVSpeechSynthesizer`, not the external `say` process, so output originates in the capture host process.
- Select an installed voice matching the detected language when available and fall back safely to the system default.
- Speak only the final one- or two-sentence answer during successful operation.
- Play a short chime as soon as a valid trigger begins processing.
- Play a distinct busy chime when a trigger is ignored because work is active.
- Speak short, non-sensitive errors for denied permissions, insufficient speech, transcription failure, OpenCode timeout/failure, malformed model output, and unrecoverable capture failure.
- Configure ScreenCaptureKit to exclude the current process's system audio so TTS is not directly fed back into the next transcript.
- Suppress or discard microphone ingestion while TTS is speaking, plus a short settling interval, to reduce acoustic feedback through external speakers.
- Do not stop system-audio capture while speaking.

### Privacy And Security Requirements

- Audio must remain in memory and must never be written to disk by `askami`.
- Do not create debug WAV files, replay files, audio archives, transcript files, prompt files, or answer logs.
- Do not persist application transcripts or answers outside OpenCode's accepted session behavior.
- Do not log sensitive content.
- Do not expose the local Whisper HTTP endpoint beyond loopback.
- Do not hardcode, print, copy, or inspect OpenCode credentials.
- Do not accept instructions from the transcript as application commands.
- Do not permit the reasoning model to execute tools.
- Bundle clear macOS microphone usage text and use a stable application identity for TCC permissions.
- Recording conversations may require consent depending on jurisdiction. Document that the user is responsible for obtaining consent.

### Packaging And Repository Requirements

- Create the project at `tools/justasec/` inside `/Users/sebastianlungu/agentikseb`.
- Use a minimal Swift Package Manager executable and package it as a locally signed, headless `.app` bundle so macOS permissions have a stable identity.
- Use bundle identifier `com.sebastianlungu.askami` unless an existing repository convention requires a more specific identifier.
- Set `LSUIElement` and avoid creating any application window, Dock icon, or menu-bar item.
- Include setup and build scripts that validate dependencies, retrieve and verify the model, build a release binary, assemble the app bundle, and apply local signing.
- Provide one documented manual start command and a clear stop method.
- Ignore downloaded model files and generated build/app artifacts in Git.
- Do not add Python, Node, Rust, OBS, virtual audio-driver, or third-party Swift runtime dependencies.
- Prefer native frameworks and Foundation networking.
- Follow repository limits: production files no more than 500 lines, functions no more than 50 lines, no more than 4 parameters, and cyclomatic complexity no more than 10.

### Performance And Reliability Requirements

- The acceptance target is that spoken output begins within 20 seconds of the hotkey after model warm-up.
- Record content-free timing metrics for snapshot/mix, transcription, OpenCode, and time-to-speech in stderr diagnostics.
- Idle capture must not continuously invoke Whisper or OpenCode.
- The Whisper model must remain warm between triggers.
- The audio buffer must remain bounded through long-running use.
- The app must terminate its Whisper child process on normal exit and interruption.
- If the Whisper server cannot start, the port is occupied, the model is missing, or a dependency is absent, fail loudly with actionable diagnostics.
- A fully resilient production recovery system for sleep/wake, every Bluetooth transition, and every device-routing edge case is out of scope; obvious stream failures must still be surfaced.

### Acceptance Criteria

1. A release build creates a launchable headless macOS app with no window, Dock icon, or menu-bar item.
2. The first run requests only the macOS permissions necessary for microphone and Screen & System Audio capture; the global hotkey does not require Accessibility permission.
3. While the process runs for at least ten minutes without triggering, audio memory remains bounded and neither Whisper inference nor OpenCode runs.
4. A phrase spoken into the microphone during the final 30 seconds appears meaningfully in local transcription.
5. A phrase played through system audio during the final 30 seconds appears meaningfully in local transcription.
6. A mixed microphone/system exchange produces one best-effort transcript without writing audio to disk.
7. `Control-Option-Space` immediately plays the trigger chime and starts exactly one analysis request while ready.
8. A second trigger during active work is ignored and produces the busy chime.
9. English and at least one non-English sample are auto-detected, answered in the same language, and spoken with a compatible voice or safe fallback.
10. When an explicit question exists, the answer addresses it in no more than two sentences.
11. When no explicit question exists, the answer states a concise useful debate verdict or insight.
12. Silence or near-silence does not reach OpenCode and produces a brief spoken error.
13. OpenCode is invoked with the pinned DeepSeek model, no external plugins, no auto-approved tools, safe process arguments, machine-readable output, and a finite timeout.
14. TTS output is excluded from direct system capture, and microphone samples produced during TTS are not retained for the next trigger.
15. After warm-up, spoken output begins within 20 seconds in a representative 30-second English test on the target M1 Pro.
16. The Whisper server listens only on loopback and terminates when the host exits.
17. No application-created audio, transcript, prompt, or answer artifact exists after successful and failed runs; OpenCode's own accepted local session history is documented as the sole exception.
18. Automated tests cover bounded retention, timestamp alignment, mixing and clipping, silence rejection, prompt construction, untrusted transcript delimiting, OpenCode JSON parsing, timeout/error mapping, and language-to-voice fallback.
19. `swift test` and the release build pass from a clean project state.
20. The README documents setup, permissions, start/stop, privacy behavior, accepted speaker-echo limitations, OpenCode persistence, troubleshooting, and the larger-model fallback.

### Explicitly Out Of Scope

- Any visible UI, settings screen, menu-bar control, Dock interface, transcript display, or clipboard workflow.
- Configurable lookback duration in v0.
- Continuous transcription or automatic unsolicited answers.
- Launch at login, system daemons, installers, notarization, App Store distribution, and production code signing.
- Windows, Linux, Intel Mac, iOS, and remote deployment.
- OBS integration, virtual audio drivers, Python, Faster-Whisper, Rust, llama.cpp, and a local reasoning LLM.
- Audio recording archives, transcript history owned by the app, replay playback, diarization, speaker identification, acoustic echo cancellation, and perfect deduplication.
- Production-grade recovery across every sleep/wake, AirPlay, protected-media, Bluetooth, and device-routing scenario.

### Evidence Sources Used To Fix The Architecture

- Apple ScreenCaptureKit provides system-audio output and, on macOS 15+, microphone output: `https://developer.apple.com/documentation/screencapturekit`.
- Apple documents microphone capture through ScreenCaptureKit: `https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone`.
- whisper.cpp 1.9.1 supports Apple Silicon, Metal, a C API, and a persistent example server: `https://github.com/ggml-org/whisper.cpp/tree/v1.9.1`.
- whisper-server 1.9.1 reads valid uploaded WAV bytes directly from request memory when conversion mode is disabled: `https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/examples/server/server.cpp`.
- OpenCode documents `run`, model selection, JSON output, pure mode, and model variants: `https://opencode.ai/docs/cli/`.

## Assumptions

1. The current machine remains the only v0 deployment target; portability is deliberately traded for speed of implementation.
2. `/opt/homebrew/bin/whisper-server` remains the executable path. Setup validates it and gives an actionable Homebrew instruction rather than installing packages silently.
3. The official multilingual Base Q5 model is stored under a Git-ignored project model directory; model weights are installation assets, not user data.
4. The implementation may select a fixed unused loopback port and fail clearly when unavailable. Dynamic service discovery is unnecessary for one local instance.
5. A locally/ad-hoc signed app bundle is sufficient for the POC. Rebuilds may occasionally require the user to re-approve TCC permissions.
6. Terminal stderr is available because startup is manual. Diagnostics contain stage names, timings, and error categories only.
7. The app may use a short post-TTS microphone suppression interval. Losing the user's microphone audio during the spoken answer is acceptable in v0.
8. The user accepts best-effort behavior with external speakers and will use headphones when duplicate acoustic speech materially hurts quality.
9. OpenCode session persistence and remote provider transmission are accepted; `askami` must not attempt risky deletion of OpenCode's shared storage.
10. The free DeepSeek model alias may become unavailable. v0 fails clearly rather than silently switching providers or models.
11. One active inference at a time is sufficient. Requests are never queued.
12. SwiftPM's built-in test support is the test framework; no UI automation framework is needed because the product has no UI.

## Subagent Pool

- **Tech Lead**: the main agent and orchestrator; owns sequencing, evidence, commits, and final report.
- **FE Engineer**: UI components, pages, client-side state, and accessibility; expected to remain unused because UI is out of scope.
- **BE Engineer**: native application lifecycle, ScreenCaptureKit, audio buffering, process control, and TTS.
- **Data/AI Engineer**: Whisper integration, transcription behavior, prompt safety, and OpenCode response parsing.
- **DevOps Engineer**: SwiftPM bootstrap, model setup, app bundling, signing, and reproducible scripts.
- **Design Artist**: visual and motion design; expected to remain unused because UI is out of scope.
- **Spec Compliance Reviewer**: independently checks behavior and scope against the full specification.
- **Code Quality Reviewer**: independently checks maintainability, tests, concurrency, resource ownership, and repository conventions.
- **Security Reviewer**: independently checks privacy, process invocation, prompt injection, local network exposure, secrets, permissions, and logging for every task.
- **QA Engineer**: integration, manual permission/capture checks, multilingual behavior, lifecycle checks, and latency evidence.

### Skills To Load

- `test-driven-development`: implement every behavior through a red-green-refactor cycle and preserve behavioral evidence.
- `swift-concurrency`: design actor/task boundaries safely and prevent callback races, blocking, leaks, and non-Sendable crossings under Swift 6.
- `systematic-debugging`: use for any capture, permission, subprocess, inference, or timing failure before changing implementation.
- `verification-before-completion`: require fresh command output before any task or final completion claim.
- `requesting-code-review`: structure evidence before dispatching the mandatory independent reviewers.
- Do not load `swiftui-expert-skill`; visible UI and SwiftUI are explicitly out of scope.
- Do not load Rust, Python, llama.cpp, frontend, browser, or Playwright skills unless the specification is formally changed.

## Gate Rubric

Every reviewer independently scores the same six dimensions.

| Dimension | Type | Pass Threshold |
|---|---|---|
| Spec compliance | Critical | >= 90 |
| Tests | Critical | >= 90 |
| Security | Critical | >= 90 |
| Code quality | Averaged | Average with Performance and Evidence >= 90 |
| Performance | Averaged | Average with Code quality and Evidence >= 90 |
| Evidence | Averaged | Average with Code quality and Performance >= 90 |

Per-reviewer pass rule: all three Critical dimensions must score at least 90, and the average of Code quality, Performance, and Evidence must be at least 90.

Cross-reviewer aggregation rule: each reviewer fills the table independently. A reviewer passes only if their own table meets the rule. A task passes only if every dispatched reviewer passes. The implementer's self-check is informational; reviewer results are authoritative.

Mandatory reviewer output format:

```markdown
| Dim | Score | Evidence |
|---|---|---|
| Spec compliance | NN/100 | file:line, test name, scan output, or runtime observation |
| Tests | NN/100 | concrete command and result |
| Security | NN/100 | concrete source/runtime evidence |
| Code quality | NN/100 | concrete source evidence |
| Performance | NN/100 | benchmark or bounded-resource evidence |
| Evidence | NN/100 | reproducible artifact or command output |

**Averaged**: (quality + performance + evidence) / 3 = NN.N
**PASS** or **FAIL**: reason
```

A score without concrete evidence is invalid. Reviewers must cite project-relative file paths, tests, scan output, process inspection, or benchmark measurements.

## Task Graph

### Task 1: Bootstrap the lightweight headless macOS project

- Intent: Establish a minimal, reproducible SwiftPM project that builds a stable headless app bundle and validates the required local tools without introducing unnecessary runtimes or dependencies.
- Acceptance: A clean setup validates Swift, Xcode, OpenCode, and whisper-server; retrieves and verifies the ignored Base Q5 model; a release build creates a locally signed app bundle with the required privacy metadata and no visible UI; `swift test` runs an initial passing test target.
- Files in scope: `tools/justasec/Package.swift`, app metadata/resources, setup/build scripts, project `.gitignore`, initial tests.
- Subagent: DevOps Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `verification-before-completion`.
- Enforcement: Do not prescribe generated project internals or script function names; verify outcomes, reproducibility, signing, and ignored artifacts.

### Task 2: Implement lifecycle, global hotkey, and bounded state transitions

- Intent: Provide the always-running manual process lifecycle and deterministic trigger behavior without requiring Accessibility permission or allowing overlapping work.
- Acceptance: The app starts headlessly, registers `Control-Option-Space`, exposes startup/ready/processing/speaking/failed behavior, accepts triggers only when ready, emits the trigger and busy chimes correctly, handles interruption, and has unit-testable state transitions.
- Files in scope: native app entry point, lifecycle/controller modules, hotkey integration, lifecycle tests.
- Subagent: BE Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `swift-concurrency`, `verification-before-completion`.
- Enforcement: Specify state behavior, not concrete type or callback names.

### Task 3: Capture microphone and system audio natively

- Intent: Continuously receive both sensitive audio sources through ScreenCaptureKit with correct permissions and format awareness while avoiding video capture and blocking callbacks.
- Acceptance: The app requests necessary TCC permissions, registers separate system and microphone outputs, receives audio without video frames, surfaces denial and stream failures, handles source format changes safely, excludes current-process system audio, and performs no inference or network work on capture queues.
- Files in scope: audio capture and conversion modules, app privacy metadata, capture-focused tests or fakes.
- Subagent: BE Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `swift-concurrency`, `systematic-debugging`, `verification-before-completion`.
- Enforcement: Do not dictate ScreenCaptureKit wrapper names or queue structure; require evidence of safe callback behavior and permission handling.

### Task 4: Build the timestamped rolling audio timeline and best-effort mixer

- Intent: Retain exactly the latest 30 seconds of both normalized audio sources in bounded memory and produce one aligned inference snapshot on demand.
- Acceptance: Independent source formats convert to 16 kHz mono Float32; timestamped retention is bounded; missing intervals render as silence; snapshots align source timelines; mixing normalizes and clips safely; a local energy gate rejects near-silence; tests cover expiry, gaps, overlap, clipping, drift-relevant timestamps, and long-running boundedness.
- Files in scope: audio conversion, timeline/buffer, mixing and WAV encoding modules, focused tests and synthetic fixtures.
- Subagent: BE Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `swift-concurrency`, `verification-before-completion`.
- Enforcement: Require deterministic behavior and memory evidence without prescribing storage data structures.

### Task 5: Integrate persistent local whisper-server transcription

- Intent: Keep the lightweight multilingual speech model warm and transcribe in-memory snapshots locally without creating audio files or exposing a network service.
- Acceptance: The app launches and readiness-checks the installed server as a child; binds only to loopback; uses the verified Base Q5 model, automatic language detection, Metal, and valid in-memory WAV multipart input; conversion mode remains disabled; structured text/language output is parsed; timeouts and failures are mapped; the child terminates with the host; tests use controlled process/network doubles plus one local integration fixture.
- Files in scope: Whisper process/client modules, configuration, STT tests and non-sensitive audio fixture, setup integration.
- Subagent: Data/AI Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `swift-concurrency`, `systematic-debugging`, `verification-before-completion`.
- Enforcement: Do not replace whisper-server with Python, Rust, direct FFI, or external STT; prove no conversion/temp-file path is active.

### Task 6: Integrate constrained OpenCode reasoning

- Intent: Turn each untrusted transcript into one safe, concise, same-language answer or debate insight through the pinned fast model without shell injection or tool execution.
- Acceptance: OpenCode is launched through safe process arguments with `--pure`, the pinned model, JSON output, no auto approval, and a finite timeout; the fixed instruction delimits untrusted transcript content and rejects embedded commands; final assistant text is parsed and validated; explicit-question and no-question prompts produce the required behavior; malformed, empty, denied, and timeout results map to safe errors; no sensitive content is logged.
- Files in scope: OpenCode process/client and prompt modules, JSON fixtures, prompt and process tests.
- Subagent: Data/AI Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `swift-concurrency`, `systematic-debugging`, `verification-before-completion`.
- Enforcement: Do not call a provider API directly, inspect credentials, enable tools, interpolate a shell command, or invent a fallback model.

### Task 7: Orchestrate hotkey-to-speech behavior and feedback suppression

- Intent: Connect capture, snapshot, local transcription, reasoning, chimes, and native TTS into the complete user journey while preventing recursive audio feedback.
- Acceptance: One ready-state hotkey produces one pipeline run; capture continues during processing; successful answers are one or two sentences and spoken with a compatible locale; system TTS is excluded from direct capture; microphone ingestion is suppressed during speech and a short settling period; processing returns to ready; all specified error categories are spoken briefly without sensitive content; stage timings are emitted without content.
- Files in scope: app orchestration, speech output, state integration, end-to-end component tests.
- Subagent: BE Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `test-driven-development`, `swift-concurrency`, `systematic-debugging`, `verification-before-completion`.
- Enforcement: Preserve the no-UI, one-active-request, RAM-only contract; do not add settings or persistence.

### Task 8: Document privacy, setup, operation, and limitations

- Intent: Make the POC operable by the owner without hidden privacy behavior or undocumented machine assumptions.
- Acceptance: Documentation covers dependency/model setup, build, permissions, manual start/stop, hotkey, chimes, privacy, remote transmission, OpenCode session persistence, consent responsibility, speaker echo limitations, Base-to-large model substitution, common startup/capture failures, and confirms all out-of-scope items remain absent.
- Files in scope: `tools/justasec/README.md`, setup/build help text, relevant ignore rules.
- Subagent: QA Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `verification-before-completion`, `requesting-code-review`.
- Enforcement: Do not claim guarantees unsupported by runtime evidence and do not include credentials or personal captured content.

### Task 9: Run full acceptance, privacy, and latency verification

- Intent: Prove the completed POC works on the target Mac, respects its privacy boundary, and starts speaking within the approved latency budget.
- Acceptance: `swift test` and release build pass; the signed bundle launches headlessly; permissions and hotkey behavior are manually verified; microphone, system, mixed, silence, busy, English, and non-English scenarios pass; the local server is loopback-only and exits cleanly; ten-minute idle use remains bounded and performs no inference; no app-created audio/transcript/prompt/answer artifacts exist; warm hotkey-to-speech begins within 20 seconds with per-stage timings; all residual limitations match explicit out-of-scope items.
- Files in scope: existing project and tests only; add no standalone report file. Evidence is returned inline to the Tech Lead.
- Subagent: QA Engineer.
- Reviewers: Spec Compliance Reviewer, Code Quality Reviewer, Security Reviewer.
- Skills to load: `systematic-debugging`, `verification-before-completion`, `requesting-code-review`.
- Enforcement: Do not weaken tests or acceptance criteria to obtain a pass; diagnose failures and return reproducible evidence.

## How To Dispatch A Subagent

- Express intent, not implementation. Say what user-visible or operational outcome must exist.
- Include the task's complete acceptance criteria and scope.
- Name exact skills to load before work; never say to load all skills.
- Require the implementer to inspect current files and preserve unrelated work.
- Never prescribe function names, variable names, internal type graphs, or line-number edits.
- Require red-green-refactor evidence, relevant build/lint output, changed-file summary, and residual concerns.
- Require the implementer to return exactly one status: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`.
- Do not dispatch dependent tasks concurrently. Only independent research or review work may run in parallel.

Use this dispatch template:

```text
TASK: <task title from graph>
INTENT: <copy from task graph>
ACCEPTANCE: <copy from task graph>
FILES IN SCOPE: <copy from task graph>
SKILLS TO LOAD FIRST: <copy from task graph>
CONTEXT: <relevant completed-task outputs and constraints from the inlined specification>
EVIDENCE REQUIRED: failing test before implementation, passing focused tests, passing broader checks, build output, changed-file list, and residual risks
RUBRIC/REVIEWERS: All six dimensions must pass; Spec Compliance, Code Quality, and Security independently inspect this task.
```

Await the subagent's report. Do not perform the same implementation work in parallel and do not advance until review gates pass or debt handling is exhausted.

## Review Loop

For every task, follow this exact order:

1. Dispatch the implementer subagent with the template above.
2. Await `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`.
3. For `NEEDS_CONTEXT`, provide the missing inlined context and re-dispatch. For `BLOCKED`, assess whether the task needs better context, a stronger model, or smaller scope, then re-dispatch without changing the specification.
4. For `DONE` or `DONE_WITH_CONCERNS`, dispatch the Spec Compliance Reviewer. Require the six-dimension table and evidence.
5. Only after the Spec Compliance Reviewer passes, dispatch the Code Quality Reviewer with the same rubric.
6. Only after Code Quality passes, dispatch the Security Reviewer. Security review is mandatory for every task.
7. A task passes only when all three reviewers independently pass. Then inspect status/diff/log, commit only that task's intended files, record the SHA, and continue.
8. If any reviewer fails, re-dispatch the implementer with the concrete failed evidence and required correction, then restart review at Spec Compliance. After the third failed review of the same task, stop retrying, file tech debt, and continue.

Never skip review order. Never infer a pass from the implementer's self-score. Never accept a reviewer score lacking reproducible evidence.

## Debt Handling

After three failed reviews of the same task, run this exact shape with the actual task evidence:

```bash
gh issue create --label tech-debt --title "Task N: <task title>" --body "$(cat <<'EOF'
## Task
<task title and intent from the task graph>

## What was tried
1. <attempt 1: what was dispatched, what failed, why>
2. <attempt 2: what was dispatched, what failed, why>
3. <attempt 3: what was dispatched, what failed, why>

## Why it failed
<root cause analysis and best current hypothesis>

## Suggested next step
<concrete recommendation: split the task, change approach, or add a justified dependency>

## Files in scope at time of failure
<project-relative list>

## Reviewer evidence
<the three failed review outputs>
EOF
)"
```

If `gh` is not authenticated, write one GitHub-issue-shaped fallback file at `docs/hoff/debt/YYYY-MM-DD-task-N.md` and include its path in the final report. Do not create any other implementation report files.

## Final Verification

After all tasks are attempted:

1. Run the complete Swift test suite from `tools/justasec/`.
2. Run a clean release build and app-bundle assembly.
3. Repeat the manual acceptance matrix from Task 9 using non-sensitive test phrases.
4. Re-check process binding, child cleanup, generated artifacts, Git ignores, and worktree status.
5. Run a fresh contextless devil's-advocate review covering specification gaps, privacy leakage, audio feedback, concurrency races, process lifecycle, and whether a simpler implementation would satisfy the same requirements.
6. Require the devil's advocate to return findings ordered by severity, practical recommendations, and a work quality score out of 100.
7. Fix Critical or High findings through the same review loop. File unresolved lower-severity findings as tech debt when justified.
8. Do not claim completion unless verification output is current and all non-debt tasks pass every gate.

## Final Report

Post only this final chat format; create no additional report Markdown file:

```text
DONE.
Tasks passed all 6 dims >=90: <X>/<N>
Tasks filed as tech-debt issues: <Y>/<N> - issues #<list>

Commits on main:
- <sha>: <message>
- ...

Build/test status: <passing|failing with debt justification>
Open follow-ups: <list>
```
