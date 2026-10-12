# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

LLLearner: an Android-only Flutter app for a French speaker learning the two languages of Taipei: **Taiwanese Hokkien** (`hok`, 台語: MOE recommended characters plus Tâi-lô) and **Taiwan Mandarin** (`man`, 華語: traditional characters, pinyin, zhuyin). The learner turns either or both on from the home screen. The UI is in French.

## Toolchain

The Flutter and Android SDKs live in `~/development/` and are not on PATH by default:

```sh
export PATH=~/development/flutter/bin:$PATH ANDROID_HOME=~/development/android-sdk
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
- The release key is in `.secrets/` (git-ignored: `release.p12`, alias `release`, PKCS12; `password.txt`; `release.p12.b64`; `fingerprint.txt`; SHA-256 `849a758d0233649d57b2290df643bcd19325d6f90505cdf974e73d66d76081ba`). CI gets it from the `RELEASE_KEYSTORE_BASE64` / `RELEASE_KEYSTORE_PASS` secrets, and a tag build fails without them. **Never regenerate or lose it**: phones refuse updates signed with another key. Without it, local release builds fall back to the debug key.
- The launcher icon is an adaptive vector only (`res/drawable/ic_launcher_*.xml`, with a monochrome layer), hence `minSdk = 26` and no PNG mipmaps. `tool/icon.svg` holds the same paths for store icons (`rsvg-convert -w 512 tool/icon.svg -o icon.png`).
- Don't add `io.flutter.embedding.android.DisableMergedPlatformUIThread` to the manifest: Flutter 3.47 crashes at startup when it's present. It used to prevent an ANR (Dart on the merged main thread blocking when another app, e.g. Claude or the share sheet, covers this one); if that ANR comes back, it needs a code fix.

## Architecture

- **State**: one global `store` (`ChangeNotifier`, in `lib/store.dart`). `Shell` in `main.dart` wraps every page in a single `ListenableBuilder`, so any store mutation (they all call `notifyListeners`) rebuilds the current tab. Tabs are swapped rather than kept in an `IndexedStack`, so page state such as the review queue or quiz is rebuilt each time the tab is entered.
- **Dictionary**: `assets/dict.db`, read-only SQLite built by the script, with tables `words(lang, pos, hanzi, roman, zhuyin, fr, tag, audio, see, moe, short)`, `defs(moe, text)`, and `examples(moe, n, hanji, roman, zh)`. At startup it's copied to the app support dir, but only when `assets/dict.version` differs from the copy's SQLite header `user_version`, so the 6 MB asset isn't read on every launch.
  - Decks: hok has about 16,800 words, man about 6,900. Each starts with hand-written themed essentials, then levels `1 · Débutant` … `6 · Expert`; hok then has `7 · Dictionnaire`, about 13,000 MOE words without a reliable French gloss, whose `Word.meaning` falls back to `short` (the first Mandarin definition). They're excluded from quizzes. New cards are introduced in `pos` order, so the order is the curriculum.
  - Only active languages are loaded into memory (`_loadDeck`, about 0.1 s on desktop for both decks). Definitions and examples are queried on demand (`store.definitions` / `store.examples`, shown by `details.dart`). The identity key is `Word.key` = `lang:hanzi`, because 學生 exists in both decks, and `store.byKey` is an O(1) index. `see` is the pre-rendered equivalent in the other language ("謝謝 xièxie"), shown on the card back even when that deck isn't loaded.
- **Regenerating the decks**: run `tool/build_words.py`, which builds both and links them; its docstring lists the downloads and the `dragonmapper` dependency.
  - Hokkien: the MOE dictionary has no French. Glosses come from CFDICT via the Mandarin synonyms in each word's first definition, used only when it's a pure synonym list (descriptive definitions produce wrong glosses). Levels come from the TOCFL level of those equivalents. The same synonyms give the cross-link; the MOE dialect-comparison table pairs words too loosely (下 ↔ 上), so it's used only for ranking.
  - Mandarin: TOCFL with CFDICT glosses. The CFDICT reading is chosen to match TOCFL's pinyin (letters and tones).
  - Hand edits live in the script, never the database: `HOK_ESSENTIALS` / `MAN_ESSENTIALS`, `HOK_LINKS`, and `FR_FIX`.
  - Licenses: the MOE dictionary is CC BY-ND 3.0 TW and CFDICT is CC BY-SA 3.0. The credit line in `lexicon.dart` is required.
- **Audio**: Mandarin uses `flutter_tts` with `zh-TW`, which needs the `TTS_SERVICE` `<queries>` entry in the manifest. There's no Taiwanese TTS voice, so for hok `play(word)` in `store.dart` downloads the MOE native-speaker recording `https://sutian.moe.edu.tw/media/senn/mp3/imtong/<word.audio>.mp3`, caches it in the app cache dir, and plays it with `audioplayers`. `word.audio` is a path: `subak/<id ÷ 1000>/<id>` for headwords, using IDs from the official `kautian.ods` (the new sutian site's numbering, which differs from the older g0v/ChhoeTaigi IDs), or `leku/…` for an example sentence. Example-sentence paths aren't in the export, so `playExample` fetches the word's page (`sutian.moe.edu.tw/zh-hant/su/<moe>/`) once and takes the n-th `leku` link: the page lists examples in the same order as the `examples` table (`ORDER BY n`). This is a deliberate scrape, so if sutian's HTML changes, example audio breaks while word audio keeps working. Hok words without a recording are silent (`Word.hasAudio`), and the UI hides their speaker buttons and listening quiz questions.
- **Persistence**: `user.db` (SQLite, WAL) in the app support dir, kept separate so dictionary updates never touch it. Uses the synchronous `sqlite3` package (FFI), not `sqflite`, whose platform channel is slow for ~24k rows.
  - `progress(key, ease, interval, reps, lapses, due)`: one row upserted per grade, covering every language.
  - `imported`: words from Claude, newest first via `added`, loaded ahead of their deck. `addWords` skips words already bundled, even in decks that aren't loaded.
  - `meta('state')`: a small JSON with active languages, mistakes, streak and daily counters.
  - `_migrate` imports the old SharedPreferences formats (`'db'`, `'state_tw'`) once, then deletes them.
  - Tests call `store.load(dir: tempDir)`.
- **SRS**: a simplified SM-2 in `nextInterval` / `applyGrade` (pure functions, covered by tests). `Store.newPerDay` caps how many new cards are introduced each day.
- **Order of `store.words`**: `_refresh` mixes the active decks level by level, alternating hok/man within a level. The level is the number at the start of `tag`; essentials and imports count as 0. The Lexique and `sessionQueue` (new cards) both use this order.
- **Store listing**: in the F-Droid repo, `../fdroid/metadata/com.eylexander.lllearner/{fr-FR,en-US}/` (fastlane names; limits: title 30, short description 80, full description 4000 characters). Keep its figures in sync with `dict.db` when the dictionary is rebuilt, and keep the "not affiliated with Anthropic" line.
- **Claude integration (`lib/coach.dart` + `MainActivity.kt`)**: deliberately **no Anthropic API**. The user wants their Claude subscription, and third-party apps can't sign in to it. Instead, the method channel `lllearner/claude` connects the two apps:
  - `openClaude`: an explicit `ACTION_SEND` to the package `com.anthropic.claude`, which opens Claude with the prompt prefilled. Prompts embed a learner profile (`_profile()`: hard words, recent mistakes, stats). If Claude isn't installed, it falls back to the `share_plus` sheet.
  - Return path: LLLearner registers as a `text/plain` share target. Text shared from Claude arrives through `takeSharedText` (cold start) or a `sharedText` callback (`onNewIntent`), and `_ShellState._fromClaude` imports it. The activity is `singleTask` on purpose: a second instance would overwrite the store with stale in-memory state.
  - Prompts follow the active languages (`_target`, `_romanization`): with both on, Claude teaches each word in both languages and must label which is which. Claude ends lessons with a JSON array `[{"lang","hanzi","roman","fr","tag"}]`. `Store.parseDeck` pulls out the first `[...]` while ignoring fences and surrounding prose; it also accepts the older `hanji`/`tailo` keys and defaults `lang` to hok. If you change that JSON format, change `_deckFormat` and `parseDeck` together.

## Content conventions

- Never mix the languages within a deck: hok uses Taiwanese words (食 tsia̍h, not 吃; 啉, not 喝) in MOE characters (臺 rather than 台 in dictionary entries); man uses Taiwan Mandarin vocabulary and pronunciation (垃圾 lèsè, 星期 xīngqí).
- Hok Tâi-lô as in the MOE dictionary: citation tones (no sandhi marked), `--` before neutral-tone syllables, and `/` between accent variants (`jua̍h/lua̍h`). Man pinyin: TOCFL words keep dictionary tones; the essentials apply 一/不 sandhi; zhuyin is generated, with the neutral-tone ˙ placed first.
- Render Han characters with the `zh()` TextStyle helper (`zh-TW` locale). Android's CJK font lacks rare characters (Ext-A/B, e.g. 𠢕 𪜶), so the theme's `fontFamilyFallback` is `RareHan` (`assets/fonts/rare_han.ttf`). It's a renamed subset of jf open huninn (OFL, license in `assets/fonts/OFL.txt`) containing only those blocks, so common characters still come from the system font. Rebuild it with `tool/build_words.py --font` when adding words whose characters it lacks.
- Quiz distractors come from the same language and must not share `roman` or `fr` with the answer.
