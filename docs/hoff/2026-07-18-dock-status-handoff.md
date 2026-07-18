# justasec Dock Status: Contextless Implementation Handoff

## Role

You are the senior tech lead for this change. You have FULL DELEGATION authority.
You do not write production code yourself except for orchestration glue.
You decompose the specification into tasks, dispatch specialized subagents, review
their work against the strict rubric below, and either pass the task or document
it as tech debt. Express intent and acceptance criteria, never line-level edits,
function names, variable names, or internal type graphs. The human is hands-off;
run the work end-to-end without asking for routine confirmation.

This is a small enhancement to an existing working macOS project, not a rewrite.
Prefer the smallest correct changes and preserve all existing audio, privacy,
process-lifecycle, and concurrency behavior.

## Project Bootstrap

Work from `/Users/sebastianlungu/justasec` on `main`.

Run these steps before dispatching implementation:

1. `cat README.md`
2. `cat AGENTS.md 2>/dev/null || echo "no AGENTS.md"`
3. `cat Package.swift`
4. `cat docs/2026-07-17-justasec-poc-handoff.md`
5. `cat docs/hoff/2026-07-18-dock-status-handoff.md`
6. `ls -la` and inspect `Sources/justasec/`, `Tests/justasecTests/`, and `scripts/`.
7. `git status --short --branch` and `git log --oneline -10`.
8. Preserve unrelated work and this handoff file. Never revert changes you did not create.
9. `git checkout main`; do not create another branch.
10. Run `swift test` and record the baseline test count.
11. Run `swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`.
12. Run `bash scripts/build.sh` and inspect the signed bundle metadata.
13. Confirm the existing bundle identifier remains `com.sebastianlungu.justasec`.
14. Identify current AppKit, Swift Testing, TDD, formatting, and commit conventions.
15. Load `test-driven-development`, `swift-concurrency`, `design-principles`, and
    `verification-before-completion` before implementation planning.

Production limits remain mandatory: files at most 500 lines, functions at most
50 lines, at most 4 parameters, and cyclomatic complexity at most 10. Use Swift
6.2 strict concurrency, native AppKit, Foundation, Carbon, and existing project
frameworks only. Add no third-party dependency.

## Specification

Source: approved Dock-status brainstorming session, July 18, 2026.

### Goal

Make the running app understandable at a glance by giving it a permanent Dock
icon whose color and central glyph communicate the current stage. Clicking the
Dock icon opens one compact native panel containing only an editable global
hotkey control and a Quit button.

The change must remain intentionally small. It must not add transcript display,
history, timings, settings navigation, a menu-bar item, launch-at-login, or any
other application UI.

### Dock Presence And Identity

- The app is visible in the Dock from launch until termination.
- It appears in Cmd-Tab as a normal macOS app.
- Remove the agent-only launch behavior that currently hides it from the Dock.
- Use the native regular application activation policy.
- Do not add a menu-bar status item.
- Preserve bundle identifier `com.sebastianlungu.justasec` and all existing TCC
  usage descriptions and entitlements.
- Add one proper base application icon to the signed app bundle and register it
  in Info.plist so the initial Dock/Finder icon is never generic.
- Runtime status changes use public AppKit APIs and do not modify the signed
  bundle or its resources after build.
- Runtime icon changes must not affect TCC identity, code signing, or privacy.

### Visual Language

Use one stable visual identity: a calm dark or neutral rounded-square base, a
high-contrast central glyph, and a state color. Color is never the only signal;
every state has a distinct glyph or shape.

The complete presentation state map is:

1. `launching`: neutral gray with an hourglass or startup glyph.
2. `listening`: blue microphone with a subtle slow pulse.
3. `stt`: violet waveform, covering snapshot/mix and local Whisper transcription.
4. `agent`: amber sparkle, covering the OpenCode reasoning stage.
5. `success`: green check, shown for 300 milliseconds with the success sound.
6. `tts`: cyan speaker with sound waves while the answer is spoken.
7. `error`: red warning glyph.

The listening animation is deliberately subtle: a cached two-frame or similarly
cheap pulse at no more than roughly two updates per second. Processing icons are
static. When macOS Reduce Motion is enabled, listening uses a static blue mic.
Respond to accessibility display-option changes while running.

Generate or cache icon images instead of redrawing expensive content on every
frame. All AppKit icon updates occur on the main actor. Leaving the listening
state stops its pulse immediately; timers/tasks must not leak or continue to
update a later state.

### Status Semantics And Sequencing

Presentation status is separate from the operational lifecycle state machine.
Do not expand or weaken trigger concurrency rules merely to drive the icon.

Required successful sequence:

1. App starts in `launching`.
2. Existing startup completes and continuous 30-second buffering begins.
3. Icon becomes `listening`.
4. A valid hotkey trigger keeps the existing trigger chime and changes to `stt`.
5. Snapshot/mix and Whisper transcription run under `stt`.
6. OpenCode reasoning changes the icon to `agent`.
7. When a valid answer is ready, microphone suppression starts before feedback.
8. Icon becomes `success`; play one short positive sound; hold for 300 ms.
9. Icon becomes `tts`; speak the answer with the existing AVSpeechSynthesizer.
10. Keep microphone suppression through speech and the existing settling interval.
11. System-audio capture continues throughout.
12. After speech and settling, return to `listening`.

The positive success sound occurs before the spoken answer because TTS is the
answer. Do not add a second completion sound after TTS.

Bundle a subtle custom ascending two-tone success chime of about 180 ms. It must
be clearly distinct from the existing trigger and busy sounds, contain no voice,
have a documented/generated provenance suitable for committing, and be copied
into the signed app bundle. Play it exactly once per successful answer.

If a trigger arrives while work is active, retain the existing busy behavior and
busy sound. The icon remains on the current active stage; do not queue work or
flash another status.

### Error Behavior

- Recoverable silence, transcription, reasoning, malformed-answer, and speech
  failures show the red warning state while the existing static spoken error is
  delivered, for at least 1.5 seconds total, then return to `listening`.
- Fatal startup, permission, capture, or unrecoverable process failures show red
  persistently until the user quits and restarts.
- Error visuals and sounds must never include transcript, prompt, answer, audio,
  credentials, or provider content.
- Preserve existing failed-state semantics and explicit diagnostics.
- Do not add automatic recovery systems outside the current POC scope.

### Compact Dock-Click Panel

A normal click on the Dock icon opens or focuses one compact native AppKit panel.
Closing the panel does not quit the app; the Dock icon remains visible.

The panel contains only:

- One labeled global-shortcut recorder/control.
- One Quit button.
- A compact inline validation error area used only when a shortcut cannot be set.

Do not show current pipeline status, transcript, answer, history, timings, privacy
content, model configuration, or navigation. The panel is fixed-size,
non-resizable, keyboard accessible, and uses native controls and focus behavior.
Its accessible labels must explain the shortcut control and Quit action.

Reopening the app from the Dock focuses an existing panel rather than creating
duplicates. Cmd-Q and the Quit button both use the same graceful termination path.

### Editable Global Shortcut

- The default remains Control-Option-Space.
- The user can record any shortcut containing at least one standard modifier
  (Control, Option, Shift, or Command) plus one non-modifier key.
- Bare keys and modifier-only shortcuts are rejected locally.
- Persist the accepted key code and modifiers in UserDefaults.
- A successful edit takes effect immediately and survives restart.
- Registration replacement is atomic from the user's perspective: test the new
  registration before discarding the old working registration.
- If the shortcut conflicts with macOS or another app, show a concise inline
  error, keep the previous shortcut registered, and do not persist the rejected
  value.
- If persisted data is malformed or cannot register at launch, fall back to
  Control-Option-Space and report a content-free diagnostic.
- Changing the shortcut while processing must not queue, cancel, or duplicate
  the active pipeline.
- Do not request Accessibility permission for shortcut registration or editing.

### Privacy, Security, And Scope Preservation

- Keep audio RAM-only and preserve the exact 30-second bounded lookback.
- Do not add transcript, prompt, or answer display or persistence.
- Do not change Whisper loopback binding, OpenCode stdin handling, tool denial,
  model selection, speech behavior, or accepted OpenCode session persistence.
- Do not add analytics, telemetry, crash reporting, or network calls.
- The panel stores only shortcut key code/modifier preferences.
- Do not log shortcut keystrokes beyond the accepted key code/modifier metadata.
- Do not add SwiftUI, a third-party shortcut recorder, animation framework, or
  visual dependency. Match the current native AppKit architecture.
- Do not redesign the audio pipeline, lifecycle, process control, or tests that
  are unrelated to status presentation and hotkey configuration.

### Acceptance Criteria

1. A release build produces a locally signed app with a non-generic base icon,
   visible in the Dock and Cmd-Tab, with no menu-bar status item.
2. Launching shows the gray startup icon; successful startup transitions to the
   blue listening mic.
3. The listening pulse is subtle, bounded, stops on state change, and becomes
   static when Reduce Motion is enabled.
4. A successful request visibly follows listening → STT → agent → success for
   300 ms → TTS → listening in that order.
5. The success chime plays exactly once before TTS and never after TTS.
6. Microphone suppression begins before the success chime and remains active
   through TTS plus settling; system capture continues.
7. Busy triggers keep the active icon, play the existing busy sound, and do not
   queue or duplicate work.
8. Recoverable errors show red for at least 1.5 seconds and return to listening;
   fatal errors remain red.
9. Clicking the Dock icon opens exactly one compact panel with only shortcut,
   inline error, and Quit controls.
10. A valid one-modifier-or-more shortcut registers immediately and persists.
11. Invalid or conflicting shortcuts leave the old shortcut active and unmodified.
12. Corrupt persisted shortcut data falls back safely to Control-Option-Space.
13. The global shortcut continues to require no Accessibility permission.
14. Runtime icon swaps do not alter bundle identity, signing, or TCC metadata.
15. All icon and panel operations are main-actor safe under Swift 6 strict mode.
16. No timer, task, window, delegate, sound, or hotkey registration leaks on
    repeated state changes, panel reopen, shortcut replacement, or termination.
17. Existing privacy, audio, Whisper, OpenCode, TTS, and artifact tests remain green.
18. Automated tests cover state mapping, stage ordering, pulse cancellation,
    Reduce Motion, recoverable/fatal errors, success timing/sound ordering,
    panel singleton behavior, shortcut validation/persistence/conflict rollback,
    and graceful Quit.
19. `swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
    passes with zero failures and warnings.
20. The strict release build and signed app-bundle assembly pass from a clean state.

### Explicitly Out Of Scope

- Transcript, answer, history, timing, or diagnostic display in the panel.
- Menu-bar item, floating overlay, notification center integration, or widgets.
- More settings than global shortcut and Quit.
- Launch at login, installer, notarization, App Store packaging, or production signing.
- Configurable lookback, model, provider, voices, colors, sounds, or animations.
- Continuous live audio meter or high-frame-rate Dock animation.
- Changes to recording consent, storage, OpenCode privacy exceptions, or model flow.
- SwiftUI or third-party UI/hotkey/icon dependencies.

## Assumptions

1. `main` remains the requested working branch; commits are made directly to it.
2. The Dock icon is visible for the entire process lifetime, including startup and fatal error.
3. A normal Dock click opens the compact panel; right-click keeps standard Dock behavior.
4. The panel may contain short static labels needed to identify the shortcut field,
   but no status text or additional settings.
5. The custom success chime is a committed application resource, not captured user audio.
6. A native generated icon renderer may use SF Symbols as status glyphs while the
   committed base `.icns` supplies Finder and pre-runtime identity.
7. The existing system trigger and busy sounds remain unchanged.
8. Recoverable error duration is the longer of spoken-error completion and 1.5 seconds.
9. The 300 ms success hold is measured with the existing injectable monotonic clock.
10. Existing TCC permission may need re-approval after rebuilding; this is normal
    ad-hoc signing behavior, not a feature regression.

## Subagent Pool

- **Tech Lead**: main orchestrator; owns sequencing, evidence, commits, and final report.
- **FE Engineer**: AppKit Dock presentation, compact panel, shortcut recorder, accessibility.
- **BE Engineer**: lifecycle/pipeline status integration and hotkey registration semantics.
- **Data/AI Engineer**: expected to remain unused; model behavior is unchanged.
- **DevOps Engineer**: icon/sound resources, Info.plist, bundle assembly, signing.
- **Design Artist**: base icon, state visual language, success-sound asset direction.
- **Spec Compliance Reviewer**: checks behavior and scope against this complete spec.
- **Code Quality Reviewer**: checks Swift 6 concurrency, ownership, tests, and limits.
- **Security Reviewer**: checks preferences, hotkey input, TCC identity, logging, privacy.
- **QA Engineer**: app-bundle, Dock, panel, state sequence, shortcut, and regression acceptance.

### Skills To Load

- `test-driven-development`: every behavior change follows red-green-refactor.
- `swift-concurrency`: AppKit main-actor boundaries, animation task ownership, cleanup.
- `design-principles`: calm, legible, trustworthy status and minimal panel behavior.
- `systematic-debugging`: any activation, Dock, hotkey, animation, signing, or TCC failure.
- `verification-before-completion`: fresh tests/build/runtime evidence before every pass.
- `requesting-code-review`: structure evidence for the mandatory reviewer sequence.
- Do not load SwiftUI, browser, frontend web, Rust, Python, or database skills.

## Gate Rubric

Every reviewer independently scores the same dimensions:

| Dimension | Type | Pass Threshold |
|---|---|---|
| Spec compliance | Critical | >= 90 |
| Tests | Critical | >= 90 |
| Security | Critical | >= 90 |
| Code quality | Averaged | Average with Performance and Evidence >= 90 |
| Performance | Averaged | Average with Code quality and Evidence >= 90 |
| Evidence | Averaged | Average with Code quality and Performance >= 90 |

Per-reviewer pass: all three Critical scores are at least 90 and the average of
Code quality, Performance, and Evidence is at least 90. A task passes only when
the Spec Compliance, Code Quality, and Security reviewers each independently pass.
The implementer's self-check is informational. A score without concrete evidence
is invalid.

Mandatory reviewer format:

```markdown
| Dim | Score | Evidence |
|---|---|---|
| Spec compliance | NN/100 | file:line, test, scan, or runtime evidence |
| Tests | NN/100 | concrete command and result |
| Security | NN/100 | concrete evidence |
| Code quality | NN/100 | concrete evidence |
| Performance | NN/100 | concrete evidence |
| Evidence | NN/100 | reproducible evidence |

**Averaged**: (quality + performance + evidence) / 3 = NN.N
**PASS** or **FAIL**: reason
```

## Task Graph

All tasks are sequential.

### Task 1: Make the app Dock-visible with a real base identity

- Intent: Convert the hidden agent into a normal Dock app while preserving its
  stable identity, headless pipeline, permissions, signing, and no-menu-bar scope.
- Acceptance: Dock and Cmd-Tab visibility from launch; non-generic bundled icon;
  regular activation; signed bundle metadata and TCC strings unchanged; no panel yet.
- Files in scope: Info.plist, app bootstrap/lifecycle, app icon resources, build script, focused tests.
- Subagent: DevOps Engineer with Design Artist input.
- Reviewers: Spec Compliance, Code Quality, Security.
- Skills to load: test-driven-development, design-principles, verification-before-completion.
- Enforcement: preserve bundle identifier and avoid unrelated pipeline changes.

### Task 2: Add the Dock status presenter and visual states

- Intent: Render and safely switch the seven approved Dock states with a calm,
  accessible color-plus-glyph language and a bounded listening pulse.
- Acceptance: every state produces a distinct cached image; all updates are main
  actor; listening pulse stops cleanly; Reduce Motion makes it static; repeated
  transitions and termination leak no timer/task; no operational state changes.
- Files in scope: Dock status presentation/rendering, lifecycle wiring seam, image tests.
- Subagent: FE Engineer.
- Reviewers: Spec Compliance, Code Quality, Security.
- Skills to load: test-driven-development, swift-concurrency, design-principles,
  verification-before-completion.
- Enforcement: presentation state remains separate from business lifecycle.

### Task 3: Integrate stage sequencing and success/error feedback

- Intent: Drive Dock states from real pipeline boundaries and add the precise
  answer-ready sound/visual sequence without changing inference behavior.
- Acceptance: exact successful order; 300 ms success hold; one custom two-tone
  chime before TTS; suppression starts before chime; recoverable/fatal error rules;
  busy behavior unchanged; deterministic fake-clock/component tests.
- Files in scope: pipeline orchestration seams, status presenter integration,
  feedback resource/playback, focused orchestration tests.
- Subagent: BE Engineer.
- Reviewers: Spec Compliance, Code Quality, Security.
- Skills to load: test-driven-development, swift-concurrency, systematic-debugging,
  verification-before-completion.
- Enforcement: no transcript/content logging and no queueing or pipeline redesign.

### Task 4: Add the compact shortcut-and-Quit panel

- Intent: A Dock click opens one native panel where the user can atomically change
  and persist the global shortcut or quit the app.
- Acceptance: singleton fixed-size panel; only shortcut, inline error, Quit;
  keyboard/accessibility labels; one-modifier-plus-key validation; persistence;
  immediate registration; conflict rollback; corrupt-data fallback; no Accessibility
  permission; panel reopen/focus and graceful Quit tests.
- Files in scope: AppKit panel/controller, shortcut value/recorder, hotkey registration
  abstraction, UserDefaults preference, app reopen handling, tests.
- Subagent: FE Engineer with BE Engineer review of Carbon registration semantics.
- Reviewers: Spec Compliance, Code Quality, Security.
- Skills to load: test-driven-development, swift-concurrency, design-principles,
  systematic-debugging, verification-before-completion.
- Enforcement: no third-party shortcut recorder and no additional settings.

### Task 5: Run regression and signed-bundle acceptance

- Intent: Prove the small UI enhancement works in the real bundle without weakening
  existing capture, privacy, pipeline, process, or strict-concurrency guarantees.
- Acceptance: all old/new tests pass; strict release and bundle/signing pass;
  Dock/panel/status sequence observed; shortcut conflict/persistence verified;
  resources present; no menu-bar item or new artifacts/network behavior; README
  updated for Dock states, panel, hotkey editing, and success sound.
- Files in scope: existing project, tests, README, scripts; no standalone report file.
- Subagent: QA Engineer.
- Reviewers: Spec Compliance, Code Quality, Security.
- Skills to load: systematic-debugging, verification-before-completion,
  requesting-code-review.
- Enforcement: do not waive prior tests or use fakes as the sole Dock/panel evidence.

## How To Dispatch A Subagent

For each task, use this template:

```text
TASK: <task title>
INTENT: <task intent>
ACCEPTANCE: <complete acceptance criteria>
FILES IN SCOPE: <scope>
SKILLS TO LOAD FIRST: <exact skills>
CONTEXT: <passed-task outputs and relevant spec constraints>
EVIDENCE REQUIRED: failing test before implementation, focused passing tests,
full strict tests/build, changed files, runtime evidence, residual risks
RUBRIC/REVIEWERS: all six dimensions; ordered Spec, Code Quality, Security reviews
RETURN: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED
```

Express outcomes, not implementation details. Require the subagent to inspect
current files and preserve unrelated work. Await its report. Never implement the
same task in parallel. Only move forward after all ordered reviews pass.

## Review Loop

For every task:

1. Dispatch the implementer.
2. Await its explicit status and evidence.
3. Resolve NEEDS_CONTEXT or BLOCKED without changing the specification.
4. Dispatch Spec Compliance Reviewer.
5. Only after Spec passes, dispatch Code Quality Reviewer.
6. Only after Code Quality passes, dispatch Security Reviewer.
7. If all pass, inspect status/diff/log, run fresh verification, stage only that
   task's files, commit on `main`, and continue.
8. If a reviewer fails, return its concrete evidence to the implementer and
   restart review at Spec Compliance.
9. After the third failed review on the same task, stop retrying, file tech debt,
   and continue. Never soften scores or skip Security.

## Debt Handling

After three failed reviews, run:

```bash
gh issue create --label tech-debt --title "Task N: <task title>" --body "$(cat <<'EOF'
## Task
<title and intent>

## What was tried
1. <attempt and failure evidence>
2. <attempt and failure evidence>
3. <attempt and failure evidence>

## Why it failed
<root cause>

## Suggested next step
<concrete recommendation>

## Files in scope at time of failure
<files>

## Reviewer evidence
<failed reviewer outputs>
EOF
)"
```

If GitHub is unavailable, write one issue-shaped fallback at
`docs/hoff/debt/YYYY-MM-DD-task-N.md` and report that path. Create no other
implementation report files.

## Final Verification

After all tasks:

1. Run full strict tests and strict release build from a clean state.
2. Assemble/sign the app and inspect Info.plist, icon resources, bundle ID, and entitlements.
3. Launch the signed app and verify Dock/Cmd-Tab presence and absence of menu-bar item.
4. Exercise all seven visual states with non-sensitive test inputs.
5. Verify success sound ordering, suppression, error persistence, and Reduce Motion.
6. Reopen the panel repeatedly; change, persist, reject, and restore shortcuts.
7. Re-run privacy/artifact/process cleanup scans and inspect worktree status.
8. Run a fresh contextless devil's-advocate review for regressions and simpler options.
9. Fix Critical/High findings through the same ordered review loop.

## Final Report

Post only:

```text
DONE.
Tasks passed all 6 dims >=90: <X>/5
Tasks filed as tech-debt issues: <Y>/5 - issues #<list>

Commits on main:
- <sha>: <message>
- ...

Build/test status: <passing|failing with debt justification>
Open follow-ups: <list>
```
