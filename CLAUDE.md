# CLAUDE.md

Guide for any Claude session continuing this project. Read it fully before changing anything.

## What this project is

A Flutter (Dart) mobile game built by a beginner as a learning project, with Claude doing most of the heavy lifting.
It is a **Flappy Bird game wrapped in a prank intro**:

1. Start screen: "Hello World! This is a test!" and a pink button "Please don't click me!".
2. Tap it: the button shakes, fades to a red "Ouch!", then the **whole screen slowly fades (about 2.2 s) into the game**.
3. Game: tap to flap through pipes. Score, best score, pause, sound on/off.
4. **Crash -> casino wheel.** The player spins a wheel (3 of 8 segments are REVIVE). REVIVE brings the bird back where it crashed, score kept, after a 3-2-1 countdown and about 1.8 s of protection. LOSE ends the run (score lost) and shows Game over -> Play again.

The entire game lives in one file: `lib/main.dart` (about 2,000 lines, no external packages). It is the real entry point, so plain `flutter run` always runs the current code.

## About the user (important for how you communicate)

- **Beginner coder.** Knows C and basic programming terms; knows booleans. Does not know Flutter/Dart jargon (widgets, state, build, etc.).
- Likes **Python comparisons** (Dart ~ Python-ish) and **C comparisons**. Explain with those, in plain words, in small steps.
- Gets overwhelmed by big code dumps ("dial it back bro"). Introduce one idea at a time; confirm before the next step.
- **Code walkthrough: only when the user asks.** They said not to start it or remind them unless they bring it up. When they do, go part by part in plain language and ask which part first; no walls of explanation.
- Casual tone, short messages. They test on an emulator and paste screenshots/terminal output back.
- The user's old scratch `main.dart` and the stale Flutter template test/README were deleted on request (2026-10-13). Nothing else in the project is scratch.

## Environment (Windows 11, set up by Claude in an earlier session)

| Thing | Value |
|---|---|
| Project | `C:\Users\Asus\dev\projects\test` (Dart package name `test`, Android package `com.example.test`) |
| Flutter SDK | `C:\Users\Asus\dev\flutter` (stable, 3.47.6 / Dart 3.13.5). `flutter\bin` is on the user PATH |
| Android SDK | `C:\Android\Sdk` (platform 36, build-tools 36.0.0). `ANDROID_HOME` and `ANDROID_SDK_ROOT` point here |
| JDK | `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot` |
| Emulators (AVDs) | `Poco_X7_Pro` (**main one**, 1220x2712, 440 dpi, 4 GB; Poco screen clone running stock Android 16 / API 36), `Poco_X6_Pro` (redundant clone), `Pixel_API36` |
| Other installed | Android Studio, VS Code (Flutter + Dart extensions), Visual Studio Build Tools 2022 (C++ workload), Git, Chrome/Edge |
| `flutter doctor` | Was clean ("No issues found") at last check |

### Critical gotchas learned the hard way

- **Claude Desktop's sandbox virtualizes writes under `AppData`.** The Android SDK first installed into `AppData\Local\Android\Sdk` was visible only to Claude, not to the user's terminal. That is why the SDK now lives at `C:\Android\Sdk`. **Never install tools or write important files under `C:\Users\Asus\AppData\...`.** Use paths like `C:\Android`, `C:\Users\Asus\dev`. Flutter's per-user config (`flutter config`) is also stored under AppData, so Claude's shell and the user's shell can have *different* Flutter settings. Verify in the user's terminal when something works for you but not for them.
- **Do not enable Windows Developer Mode, and do not change system settings.** Any pub package that includes a native plugin (for example `google_fonts` via `path_provider`, `audioplayers`, `shared_preferences`) makes Flutter on Windows demand Developer Mode (symlinks). That is a system setting the assistant must not change, so **avoid plugin packages**. Pure-Dart packages are fine. If a plugin is truly needed, ask the user to enable Developer Mode themselves.
- **Never launch the same AVD twice.** It fails with "Running multiple emulators with the same AVD" (and `flutter emulators --launch` hides the real error, printing a blank "exited with code 1"). Check with `adb devices` / `flutter devices` first. If an emulator is stuck, clear stale lock files in `C:\Users\Asus\.android\avd\<name>.avd\` (`*.lock`).
- **The emulator is slow.** First boot of an AVD takes several minutes; cold-launching the app can take about 25 s. Wait for it before sending taps (taps sent during the Flutter splash are lost).
- A running `flutter run` / debug session holds the Gradle build; stop it before a clean rebuild if you hit lock errors.
- Downloads/installs need the user's explicit permission. Do not modify system settings, enter credentials, or delete user data without asking.

## Common commands (PowerShell, from the project root)

```powershell
cd C:\Users\Asus\dev\projects\test

# run the game
flutter run                                          # pick the emulator when asked
flutter run -d emulator-5554

# start the main emulator (wait ~3-5 min the first time; do not relaunch while it boots)
flutter emulators --launch Poco_X7_Pro
# or directly (shows real errors):  & "C:\Android\Sdk\emulator\emulator.exe" -avd Poco_X7_Pro

flutter devices
flutter analyze                                      # must stay "No issues found"
flutter build apk --debug                            # compile check incl. Kotlin
```

- In VS Code: open `lib/main.dart` and click **Run** above `void main`.
- **Hot reload (`r`) does not apply to** `main()`, state-class field changes, or any Kotlin change. Use hot restart (`R`) or a full re-run. Changes to `MainActivity.kt` need a full rebuild.
- `adb`: `C:\Android\Sdk\platform-tools\adb.exe`. Screen is **1220x2712 px**.

## Layout

```
lib/main.dart            the whole game (see architecture below)
assets/fonts/            Fredoka + Nunito (OFL), declared in pubspec.yaml
android/app/src/main/kotlin/com/example/test/MainActivity.kt   native sound player
pubspec.yaml             no extra dependencies (only flutter + template ones)
CLAUDE.md                this file
```

## Architecture of `lib/main.dart`

Top to bottom:

1. **`main()` / `FlappyApp`** - Material 3, light + dark themes following the system, text scaling clamped to 1.0-1.3 so cards never overflow.
2. **`Sfx`** - sound engine. All sound effects are **synthesized in Dart** (sine/square sweeps and noise -> 16-bit mono PCM @ 22,050 Hz) in `Sfx.bank`. `Sfx.init()` sends them over `MethodChannel('flappy/sfx')` (`load`), `Sfx.play(name)` triggers them (`play`). Names: `flap score hit tick tap win lose beep go milestone best pause`. The best score is saved natively via `MethodChannel('flappy/save')` (`getBest`/`setBest`, Android SharedPreferences, no plugin). On non-Android platforms the calls fail safely and are ignored. `Sfx.enabled` is the mute flag.
3. **`Palette` + `heading()` / `body()`** - every colour and text style. **No hard-coded colours elsewhere.** `Palette.of(context)` picks light/dark. The bird's colours are constants shared by both modes.
4. **`ClayButton`, `ClayCard`** - the reusable claymorphism widgets. Buttons are at least 56 dp tall, have a pressed state, play a `tap` sound, and set semantics.
5. **`StartPage`** (`Phase.start -> ouch -> game`) - the prank intro. `AnimatedSwitcher` provides the long fade into `GameScreen`.
6. **`SpinWheelCard`** + `_WheelPainter` / `_PointerPainter` - the casino wheel (custom painted). Top-level `Random wheelRandom` is the random source (tests swap it for a fixed one). Segment kinds: `kinds = [true,false,false,true,false,true,false,false]` (`true` = REVIVE). The target angle is `2*pi*turns - (k*seg + seg/2 + offset)`, so it always stops inside the chosen segment under the pointer. A tick sound plays each time a segment passes the pointer.
7. **`GameScreen`** - the game. Key points:
   - `GState`: `ready -> playing <-> paused`, `playing -> crashed -> (wheel) -> reviving -> playing` or `-> dead -> ready`.
   - Driven by a **`Ticker`** (frame-synced) with **delta-time physics** (`dt` capped at 0.05 s). Only the world layer rebuilds each frame (`ValueNotifier<int> frame` + `ValueListenableBuilder` inside a `RepaintBoundary`); HUD/overlays rebuild with `setState` only on state changes.
   - Tweakables are `static const` at the top of `_GameScreenState` (`gravity`, `flapSpeed`, `pipeW`, `spacing`, ...). `currentGap` shrinks and `speed` grows with score.
   - Collision uses a hit radius smaller than the drawn bird (forgiving). Pipe caps are decorative overhang.
   - `_crash()` freezes the world. `_revive()` keeps the bird at the same X and **only nudges Y if it would die instantly** (inside a pipe or on the floor). `invincible = 1.8` s after the countdown (the bird blinks, pipes pass through, the floor holds it up). `_lose()` sets `best`/`newBest`. **`best` updates only on final loss.**
   - Auto-pauses on app background (`WidgetsBindingObserver`). Respects reduced-motion (`MediaQuery.disableAnimationsOf`): no shake, cloud drift, wing flap, or pulse, and short fades.
   - Haptics via `HapticFeedback`.

### Native sound (`MainActivity.kt`)

Kotlin `MethodChannel("flappy/sfx")`: `load(name, data)` stores PCM bytes; `play(name)` creates a static-mode `AudioTrack` on a short thread, plays, waits, releases. It logs `D/sfx: played N frames, device consumed M` (tag `sfx`). **`N == M` means the device played the whole sound.** Check with `adb logcat -d -s sfx`. No permissions or plugins needed.

## Design system (from the UI/UX Pro Max skill)

Source: GitHub `nextlevelbuilder/ui-ux-pro-max-skill` (MIT; it is local data + a Python search script with no network calls). It was cloned into a temporary scratch folder only (**not installed**), run via `search.py "<query>" --design-system` and `--stack flutter`, and is probably gone now. Re-clone only if the user wants more searches, and read the files before running anything. Do not run its npm global installer.

Result applied: **Claymorphism** (soft 3D, chunky 3-4 px borders, double shadows, 16-28 px radii, soft press about 140 ms). Palette: pink `#EC4899` (black text on it for contrast), violet `#8B5CF6`, gold `#F59E0B`, background `#FDF2F8`, text `#0F172A`; sunset sky gradient; night-sky dark mode. Typography intent: Fredoka (headings) + Nunito (body); bundled as variable fonts in `assets/fonts/` (OFL) and declared in `pubspec.yaml`.
Checklist rules the code follows: touch targets of at least 56 dp, press feedback, contrast of at least 4.5:1, reduced-motion support, semantic labels / live regions, safe areas, dark mode tested separately, no emoji icons, semantic tokens only.

## How to test (what worked)

1. **Static:** `flutter analyze` -> must be clean.
2. **Widget tests (headless).** The previous session used a throwaway copy of the project (`flappy_check` in the scratchpad) with `lib/main.dart` = the game and `test/flappy_test.dart`; recreate that or add a test file importing `package:test/main.dart`. Patterns:
   - Set a phone-size view (`tester.view.physicalSize = Size(1080, 2400)`, `devicePixelRatio = 2.75`).
   - Pump with **16 ms frames** (`for (...) await tester.pump(Duration(milliseconds: 16))`). Larger steps get clamped by the `dt` cap, making timers (countdown, invincibility) take longer than expected.
   - Force the wheel: `class FixedRandom implements Random { nextInt(8) -> segment; nextDouble() -> 0.5 }`, then `wheelRandom = FixedRandom(0)` (REVIVE) or `FixedRandom(1)` (LOSE); reset in `tearDown`.
   - Also assert `Sfx.bank` has all 9 sounds, non-silent, not clipped, even length.
   - End tests with `await tester.pumpWidget(Container())` to dispose the Ticker.
3. **On the emulator, with adb** (all verified in the previous session):
   - Screenshot: `adb exec-out screencap -p > file.png` (run through `cmd /c` in PowerShell so the binary is not mangled).
   - Taps: `adb shell input tap X Y` in **device pixels (1220x2712)**. The intro button is about (612, 1489); the wheel's SPIN / Continue button about (612, 1890).
   - Dark mode: `adb shell cmd uimode night yes|no` (**set it back to `no` afterwards**).
   - Install a test build under a different package so the user's app is untouched, and uninstall it after.
   - Sound check: `adb logcat -d -s sfx`.

## Conventions

- Keep the game in one file unless the user asks to split it; keep comments friendly and beginner-readable (the user reads the code).
- Colours only via `Palette`; text via `heading()` / `body()`; buttons via `ClayButton`.
- No new plugin packages (see Developer Mode above). Pure-Dart only.
- Never leave the analyzer dirty. Re-run the emulator check after gameplay changes. Verify before claiming it works, and say plainly what was and was not verified.
- Do not touch git settings without asking. The project is not a git repository (as of this writing).

## Known gaps / ideas (not done)

- Sound is Android-only; effects are simple synthesized beeps (no music).
- Art is shapes only (no sprites). Possible polish: parallax ground/hills, bird death particles, confetti on REVIVE, wheel odds/rewards variants, difficulty settings.
- Remove the redundant `Poco_X6_Pro` AVD if the user wants (a duplicate of the X7 Pro screen).
- A leftover 5.7 GB copy of the SDK sits in Claude's private package cache (invisible to the user's folders); offer to delete it if disk space matters.
- Poco X7 Pro screen specs (1220x2712, about 446 ppi) were recalled from memory, not verified.

## Behaviour verified on the emulator (2026-10-13)

Intro prank (1 s fade) -> game -> crash card (Spin the wheel / Play again / Quit) -> wheel -> REVIVE (3-2-1 countdown, confetti, blinking protection) or LOSE (Game over card: Play again / Quit). **Quit closes the app to the phone home screen** (SystemNavigator.pop; best score saved first). The pause card (pause button top right, Esc, or Android Back) has Resume / Quit. Best score persists across launches. Hills, feathers, confetti, fonts and the music loop all render/play.

**Esc gotcha:** Android swallows the first Esc before Flutter sees it, so MainActivity.dispatchKeyEvent catches Esc and sends it over MethodChannel('flappy/keys') to Sfx.onEscape. Do not move this back to Dart Focus/HardwareKeyboard; that was flaky.

**Testing gotchas:** db input tap is slow (about 0.3 s each), so scripted flapping rarely keeps the bird alive; test pause by tapping to start then Esc as a separate adb call. Installing with db install -r of the debug APK is what the launcher icon runs; hot reload changes are NOT in it, so always do a full rebuild/install before judging what the user sees (a stale installed build caused a "bug" report once).
