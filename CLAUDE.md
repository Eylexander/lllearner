# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

LLLearner: an Android-only Flutter app for a French speaker learning languages, organized in **courses** like the big language apps. There is one course, **Taiwan Mandarin** (`man`, 華語: traditional characters, pinyin, zhuyin). Taiwanese Hokkien was dropped (its progress rows may linger in old `user.db` files, unused). The UI is in French.

## Toolchain

CI uses Flutter 3.47.7 (Dart 3.13). On the Windows dev PC, `~/SDKs/flutter` is older and can't resolve the project; use `~/SDKs/flutter-3.47.7`. The Android SDK is in `%LOCALAPPDATA%/Android/Sdk` (AVD `Medium_Phone_API_36.0`), and Android Studio's JDK in `%LOCALAPPDATA%/Programs/Android Studio/jbr`:

```sh
export PATH=~/SDKs/flutter-3.47.7/bin:$LOCALAPPDATA/Android/Sdk/platform-tools:$PATH \
  ANDROID_HOME=$LOCALAPPDATA/Android/Sdk JAVA_HOME="$LOCALAPPDATA/Programs/Android Studio/jbr"
flutter build apk --debug --target-platform android-x64   # for the emulator
```

## Commands

```sh
flutter analyze                                   # lint (flutter_lints)
flutter test                                      # all tests
flutter test test/store_test.dart --name parseDeck # single test
dart format -l 120 lib test                       # code uses 120-col lines
flutter build apk --release --target-platform android-arm64   # → build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Releasing (same scheme as the user's Audio Cutter, `Eylexander/audio_player`)

- Package `com.eylexander.lllearner`. Distributed through the user's F-Droid repo (`../fdroid`, GitHub `Eylexander/fdroid`), which picks up GitHub releases of `Eylexander/LLLearner` within 6 hours. The store listing (fr-FR, en-US) and the 512 px icon live there in `metadata/com.eylexander.lllearner/`, not in this repo.
- Push a `v*` tag. `.github/workflows/release.yml` runs analyze and test, then builds one arm64 APK. The version name comes from the tag, the versionCode is the run number (it must keep increasing), and the APK is published as a GitHub release.
- The release key is in `.secrets/` (git-ignored: `release.p12`, alias `release`, PKCS12; `password.txt`; `release.p12.b64`; `fingerprint.txt`; SHA-256 `db171ead795079f5e07d32cdc553f7eae42e60f4b29d0385c423eb6937837199`). It is the same key as Audio Cutter's (`../fossify/.secrets/`): v1.0.0 was published with it, so LLLearner must keep it. CI gets it from the `RELEASE_KEYSTORE_BASE64` / `RELEASE_KEYSTORE_PASS` secrets, and a tag build fails without them. **Never regenerate or lose it**: phones refuse updates signed with another key. Without it, local release builds fall back to the debug key.
- The launcher icon is an adaptive vector only (`res/drawable/ic_launcher_*.xml`: a speech bubble holding 文 in single-weight strokes on vermilion; the foreground doubles as the monochrome layer for themed icons), hence `minSdk = 26` and no PNG mipmaps. `tool/icon.svg` holds the same paths for store icons (`rsvg-convert -w 512 tool/icon.svg -o icon.png`). Launch styles follow light/dark; on Android 12+ the splash background is the system's neutral color.
- Don't add `io.flutter.embedding.android.DisableMergedPlatformUIThread` to the manifest: Flutter 3.47 crashes at startup when it's present. It used to prevent an ANR (Dart on the merged main thread blocking when another app, e.g. Claude or the share sheet, covers this one); if that ANR comes back, it needs a code fix.

## Architecture

- **Courses** (`lib/course.dart`): everything language-specific (names, TTS locale and voice name, glyph locale, romanization, greetings, Claude role-play scenarios, the tips shown before the first lesson) lives in a `Course`. A course's words are the `dict.db` deck whose `lang` is its id, and its progress keys are `id:hanzi`. Adding a language = a deck from the build script + an entry in `courses`. One course is active at a time (`store.course`); the switcher is in the top app bar (`showCourseSheet`).
- **State**: one global `store` (`ChangeNotifier`, in `lib/store.dart`). `Shell` in `main.dart` wraps the tabs (Apprendre, Réviser, Pratiquer, Lexique, Assistant) in a single `ListenableBuilder`, so any store mutation rebuilds the current tab. Lessons, review sessions and quizzes are pushed routes, so their state survives tab rebuilds. Settings (daily goal, pinyin/zhuyin, tone colors, hints, speech rate, theme) are store fields changed through `store.set(...)`; appearance changes also bump `store.appearance`, the only thing `MaterialApp` listens to. First launch shows `Onboarding` (course, goal, pronunciation, voice check).
- **Theme** (`lib/theme.dart`): Material 3 from `ColorScheme.fromSeed`, seeded by the wallpaper's primary (`dynamic_color`, Android 12+) or one of `seeds`. Never hardcode colors: semantic ones (success, warning, streak, the four tone colors) come from the `Palette` theme extension (`context.palette`); success, warning and streak are harmonized with the primary. The others use tonal spot so their containers stay light; the tone colors are fixed per brightness (not harmonized), chosen to stay distinct for color-blind users (protanopia, deuteranopia, tritanopia), so recheck that with a simulator if you change them.
- **Dictionary**: `assets/dict.db`, read-only SQLite built by the script, with tables `words(lang, pos, hanzi, roman, zhuyin, fr, tag)`, `sentences(id, hanzi, roman, fr)` and `examples(lang, hanzi, n, sid)`. At startup it's copied to the app support dir, but only when `assets/dict.version` differs from the copy's SQLite header `user_version`, so the asset isn't read on every launch.
  - The Mandarin deck has about 6,900 words: hand-written themed essentials, then TOCFL levels `1 · Débutant` … `6 · Expert`. Words are taught in `pos` order, so the order is the curriculum.
  - Only the current course's deck is in memory (`_loadDeck`). Example sentences are queried on demand and cached (`store.examples`); words without chosen examples (imports) fall back to any sentence containing them. The identity key is `Word.key` = `lang:hanzi`, and `store.byKey` is an O(1) index.
- **Lessons and units** (`_refresh`): words are grouped by tag (imports by Claude's tag, first), cut into lessons of `Store.lessonSize` words, and long tags into units of `Store.lessonsPerUnit` lessons ('Débutant · 2/7'); units carry the section they're listed under on the home path. `nextLesson` is the first lesson with a new word. `LessonPage` introduces each new word (characters, pronunciation, audio, first example), practises them three at a time, then all together; misses are re-asked (twice at most) and recorded as mistakes. Words enter SRS only when the lesson ends (`store.learn`: good, or hard if missed; "Je connais déjà" = `markKnown`, easy). The course's `tips` are shown before the very first lesson.
- **Exercises** (`lib/exercise.dart`): meaning, recall, listen, tones. Reviews and quizzes only ever ask about learned words. Wrong options come from `distractorPool` (the given words, learned words, and the 30 words around each target in course order, never the whole deck), preferring words already seen and the same tag, and never sharing the sound or the first French sense with the answer. Tone exercises change one or two tone marks (`toneVariants`).
- **Pinyin** (`lib/pinyin.dart`): `syllables` splits pinyin into syllables with tones (a DP over the syllable inventory, penalizing vowel-initial syllables inside a word, where pinyin would use an apostrophe). It drives the tone colors on pinyin and, when the counts match, on characters (`Hanzi`, `Roman`, `Zhuyin` widgets). A test checks that every deck word parses; add Taiwan-specific syllables to `_valid` if it fails.
- **Regenerating the dictionary**: run `tool/build_words.py`; its docstring lists the downloads (CFDICT, TOCFL, Tatoeba) and the `dragonmapper` / `opencc-python-reimplemented` dependencies.
  - Mandarin: TOCFL with CFDICT glosses. The CFDICT reading is chosen to match TOCFL's pinyin (letters and tones).
  - Examples: Tatoeba Mandarin–French pairs converted to Taiwan characters (OpenCC `s2twp`), segmented greedily with the deck (Taiwan readings) then CFDICT; sentences with a character it can't read are dropped rather than guessed. Up to 3 per word, preferring short ones whose other words are no harder than the word.
  - Hand edits live in the script, never the database: `MAN_ESSENTIALS`, `FR_FIX`, `PARTICLES`.
  - Licenses: CFDICT is CC BY-SA 3.0, Tatoeba CC BY 2.0 FR. The credit lines in `lexicon.dart` and the settings page are required.
- **Audio**: the phone's TTS (`flutter_tts`) with the course's locale (`zh-TW`), which needs the `TTS_SERVICE` `<queries>` entry in the manifest; `speak` sets the language on every call. If the voice is missing, a snackbar and the settings offer `openTtsSettings` (channel `lllearner/android` in `MainActivity.kt`). The app needs no network permission.
- **Persistence**: `user.db` (SQLite, WAL) in the app support dir, kept separate so dictionary updates never touch it. Uses the synchronous `sqlite3` package (FFI), not `sqflite`, whose platform channel is slow for thousands of rows.
  - `progress(key, ease, interval, reps, lapses, due)`: one row upserted per grade, covering every course.
  - `imported`: words from Claude, newest first via `added`, loaded ahead of their deck as the next lessons. `addWords` skips words already bundled.
  - `meta('state')`: a JSON with the course, settings, mistakes, streak, active days and daily counters. `_read` also accepts the pre-course format (`active` languages → the first one that is still a course).
  - `_migrate` imports the old SharedPreferences format (`'db'`) once, then deletes it.
  - Tests call `store.load(dir: tempDir)`, then `store.close()` (Windows can't delete open files).
- **SRS**: a simplified SM-2 in `nextInterval` / `applyGrade` (pure functions, covered by tests). Once nothing is due, the Réviser tab offers reviewing ahead (`store.ahead`: the next 20 cards to come up); an early grade grows from the time actually elapsed, not the scheduled interval. `dailyGoal` is a target shown on the home card, not a cap.
- **Store listing**: in the F-Droid repo, `../fdroid/metadata/com.eylexander.lllearner/{fr-FR,en-US}/` (fastlane names; limits: title 30, short description 80, full description 4000 characters). Keep its figures in sync with `dict.db` when the dictionary is rebuilt, and keep the "not affiliated with Anthropic" line.
- **Claude integration (`lib/coach.dart` + `MainActivity.kt`)**: deliberately **no Anthropic API**. The user wants their Claude subscription, and third-party apps can't sign in to it. Instead, the method channel `lllearner/claude` connects the two apps:
  - `openClaude`: an explicit `ACTION_SEND` to the package `com.anthropic.claude`, which opens Claude with the prompt prefilled. Prompts embed a learner profile (`_profile()`: hard words, recent mistakes, stats). If Claude isn't installed, it falls back to the `share_plus` sheet.
  - Return path: LLLearner registers as a `text/plain` share target. Text shared from Claude arrives through `takeSharedText` (cold start) or a `sharedText` callback (`onNewIntent`), and `_ShellState._fromClaude` imports it. The activity is `singleTask` on purpose: a second instance would overwrite the store with stale in-memory state.
  - Prompts are built from the current course (`Course.claude`, `romanization`, `scenarios`). Claude ends lessons with a JSON array `[{"lang","hanzi","roman","fr","tag"}]`. `Store.parseDeck` pulls out the first `[...]` while ignoring fences and surrounding prose; `lang` defaults to the current course, and entries in a language that isn't a course are skipped. If you change that JSON format, change `_deckFormat` and `parseDeck` together.

## Content conventions

- Taiwan Mandarin vocabulary and pronunciation (垃圾 lèsè, 星期 xīngqí, 腳踏車, 捷運) in traditional characters. TOCFL words keep dictionary tones; the essentials apply 一/不 sandhi; zhuyin is generated, with the neutral-tone ˙ placed first.
- Render text in the course language with the `script()` TextStyle helper (it sets the course locale, so Taiwan glyph forms are used), and words with `Hanzi` / `Pronunciation` so tone colors and the pinyin/zhuyin setting apply.
- Exercise options must not share `roman` or the first French sense with the answer.
