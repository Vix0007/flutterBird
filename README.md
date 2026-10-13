# Flutter Bird

A Flappy Bird game made with Flutter, wrapped in a prank intro and with a casino wheel that decides whether you get a second chance.

## How it plays

1. **The prank.** The app opens on "Hello World! This is a test!" and a button that says "Please don't click me!". Press it and the screen fades into the game.
2. **Fly.** Tap to flap and get through the pipes. The gap shrinks and the speed grows as your score goes up.
3. **Crash.** You get three choices:
   - **Spin the wheel.** 3 of the 8 segments are REVIVE. REVIVE puts the bird back where it crashed, with your score kept, after a 3-2-1 countdown and a short blinking protection window. LOSE ends the run.
   - **Play again.** Skip the wheel and start a new run.
   - **Quit.** Close the app.
4. **Best score** is saved between launches.

## Controls

| Action | How |
|---|---|
| Flap | Tap the screen |
| Pause / resume | Pause button (top right), `Esc`, or the Android Back button |
| Mute / unmute | Speaker button (top left) |

## Features

- Sound effects and a looping background tune, all generated in code (no audio files)
- Claymorphism look with light and dark themes
- Parallax hills, crash feathers and revive confetti
- Respects the system "reduce motion" setting
- No third-party packages, so no Windows Developer Mode needed

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) and an Android emulator or phone. The game is Android only, because the sound and the saved best score use a small piece of native Android code.

```bash
flutter pub get
flutter run
```

Other useful commands:

```bash
flutter analyze                 # static checks
flutter build apk --debug       # build an APK
```

## Project layout

```
lib/main.dart                                      the whole game
android/app/src/main/kotlin/.../MainActivity.kt    native sound, music, saved score, Esc key
assets/fonts/                                      Fredoka and Nunito fonts
pubspec.yaml                                       app config and font declarations
```

## Credits

Fonts: [Fredoka](https://fonts.google.com/specimen/Fredoka) and [Nunito](https://fonts.google.com/specimen/Nunito), both under the SIL Open Font License.
