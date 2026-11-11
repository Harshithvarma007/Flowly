# Contributing to Flowly

Thanks for helping out! Flowly is a small Swift package, so getting started is quick.

## Setup

Requirements: macOS 14+, Apple Silicon, Xcode 15+ (or the Swift 5.9+ toolchain).

```bash
git clone https://github.com/Harshithvarma007/Flowly.git
cd Flowly
swift build            # debug build
./scripts/build_app.sh # release .app bundle in dist/
```

## Before you open a pull request

1. `swift build -c release` completes without new warnings.
2. If you touched the cleanup prompt or `TextProcessor`, run the eval set and make sure the score does not drop:
   ```bash
   dist/Flowly.app/Contents/MacOS/Flowly --eval tests/polish_cases.json ollama qwen3.5:4b
   ```
3. Found a dictation that comes out wrong? Add it to `tests/polish_cases.json` first, then fix the prompt or rules.
4. Keep privacy intact: no network calls with audio, never read password fields, no telemetry.

## Style

- Plain Swift, SwiftUI for UI, no extra dependencies unless clearly justified.
- Small focused commits with imperative messages ("Fix latch timeout").

## Reporting bugs

Open an issue with your macOS version, Mac model, and the relevant lines from `~/Library/Application Support/Flowly/debug.log` (remove anything private).
