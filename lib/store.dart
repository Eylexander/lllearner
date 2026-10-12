import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:sqlite3/sqlite3.dart' as sql show Row;

import 'course.dart';

/// A word of a course's deck: characters, romanization (pinyin), French gloss, and its
/// theme or level tag ('Salutations', '3 · Élémentaire', or Claude's tag for imports).
class Word {
  Word(this.lang, this.hanzi, this.roman, this.fr, this.tag, {this.zhuyin = '', this.imported = false});

  final String lang, hanzi, roman, zhuyin, fr, tag;
  final bool imported; // added from a Claude reply
  double ease = 2.5;
  double interval = 0; // days
  int reps = 0, lapses = 0;
  DateTime? due; // null = not learned yet
  late final String searchKey = plain('$roman $zhuyin $fr $tag');

  String get key => '$lang:$hanzi';
  bool get isNew => due == null;
  bool get mastered => interval >= 21;
  bool get weak => !isNew && (lapses > 0 || ease < 2.3);

  /// '3 · Élémentaire' → 3; themed essentials and imports → 0.
  int get level => int.tryParse(tag.split(' ').first) ?? 0;

  factory Word.fromRow(sql.Row r, {bool imported = false}) =>
      Word(r['lang'], r['hanzi'], r['roman'], r['fr'], r['tag'], zhuyin: r['zhuyin'] ?? '', imported: imported);
}

enum Grade { again, hard, good, easy }

/// Next interval in days (simplified SM-2). A card reviewed ahead of time grows from the time
/// actually elapsed since its last review, never below its current interval when it's known.
double nextInterval(Word w, Grade g, DateTime now) {
  final early = w.due != null && w.due!.isAfter(now);
  final elapsed = early ? max(0.0, w.interval - w.due!.difference(now).inMinutes / 1440) : w.interval;
  final good = w.reps == 0
      ? 1.0
      : w.reps == 1
      ? 3.0
      : max(w.interval, elapsed * w.ease);
  return switch (g) {
    Grade.again => 0.0,
    Grade.hard => w.reps == 0 ? 0.25 : max(1.0, elapsed * 1.2),
    Grade.good => good,
    Grade.easy => max(4.0, good * 1.3),
  };
}

void applyGrade(Word w, Grade g, DateTime now) {
  final next = nextInterval(w, g, now);
  if (g == Grade.again) {
    w.reps = 0;
    w.lapses++;
    w.ease = max(1.3, w.ease - 0.2);
    w.interval = 0;
    w.due = now.add(const Duration(minutes: 1));
    return;
  }
  w.ease = (w.ease + const {Grade.hard: -0.15, Grade.good: 0.0, Grade.easy: 0.15}[g]!).clamp(1.3, 3.0);
  w.reps++;
  w.interval = next;
  w.due = now.add(Duration(minutes: (next * 1440).round()));
}

String formatInterval(double d) => d == 0
    ? '1 min'
    : d < 1
    ? '${(d * 24).round()} h'
    : d < 30
    ? '${d.round()} j'
    : d < 365
    ? '${(d / 30).round()} mois'
    : '${(d / 365).toStringAsFixed(1)} an';

typedef Example = ({String hanzi, String roman, String fr});

/// A few new words taught together: introduced one by one, then practised.
class Lesson {
  Lesson(this.unit, this.number, this.words);
  final Unit unit;
  final int number; // within its unit, from 1
  final List<Word> words;

  bool get done => words.every((w) => !w.isNew);
  int get learned => words.where((w) => !w.isNew).length;
}

/// A run of lessons on one theme, or one part of a level ('Débutant · 2/6').
class Unit {
  Unit(this.section, this.title, {this.part = 1, this.parts = 1});
  final String section; // heading the unit is listed under
  final String title;
  final int part, parts;
  final List<Lesson> lessons = [];

  String get name => parts > 1 ? '$title · $part/$parts' : title;
  Iterable<Word> get words => lessons.expand((l) => l.words);
  int get size => lessons.fold(0, (n, l) => n + l.words.length);
  int get learned => lessons.fold(0, (n, l) => n + l.learned);
}

enum Pron { pinyin, zhuyin, both }

/// Two SQLite databases in the app support dir:
/// - dict.db: read-only copy of assets/dict.db (words of every course, example sentences),
///   recopied when assets/dict.version changes;
/// - user.db: progress(key, …) one row per learned word, imported (words from Claude),
///   meta('state' → JSON: course, settings, mistakes, streak and daily counters).
/// The current course's deck is held in memory; example sentences are queried on demand.
class Store extends ChangeNotifier {
  static const lessonSize = 6, lessonsPerUnit = 8;

  late final Database dict, _db;
  Course course = courses.first;
  final Map<String, List<Word>> _decks = {};
  final Map<String, Word> _byKey = {};
  List<Word> words = []; // current course, in study order (imports first)
  List<Unit> units = [];
  List<String> mistakes = []; // keys, most recent first
  int _streak = 0, _newToday = 0;
  String _lastDay = '';
  List<String> days = []; // days with activity, most recent last (for the streak calendar)

  // Settings.
  bool onboarded = false;
  int dailyGoal = 10; // new words a day
  Pron pron = Pron.pinyin;
  bool toneColors = true;
  bool hints = true; // pronunciation shown in exercises
  double speechRate = 0.42;
  ThemeMode themeMode = ThemeMode.system;
  bool dynamicColor = true;
  int seed = 0;

  /// Bumped when an appearance setting changes, so only then the app's theme is rebuilt.
  final appearance = ValueNotifier(0);

  /// [dir] is for tests (a temp dir); the app uses its support directory.
  Future<void> load({String? dir}) async {
    dir ??= (await getApplicationSupportDirectory()).path;
    dict = await _openDict(dir);
    _db = sqlite3.open('$dir/user.db')
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA synchronous = NORMAL')
      ..execute(
        'CREATE TABLE IF NOT EXISTS progress(key TEXT PRIMARY KEY, ease REAL, interval REAL, reps INTEGER, '
        'lapses INTEGER, due INTEGER)',
      )
      ..execute(
        'CREATE TABLE IF NOT EXISTS imported(lang TEXT, hanzi TEXT, roman TEXT, zhuyin TEXT, fr TEXT, tag TEXT, '
        'added INTEGER, PRIMARY KEY(lang, hanzi))',
      )
      ..execute('CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT)');
    final state = _db.select("SELECT v FROM meta WHERE k = 'state'").firstOrNull;
    if (state == null) {
      await _migrate();
    } else {
      _read(jsonDecode(state['v']) as Map, onboarded: true);
    }
    _loadDeck(course.id);
    _refresh();
  }

  /// Closes both databases (tests: so their directory can be deleted on Windows).
  void close() {
    dict.close();
    _db.close();
  }

  /// The state JSON. Older versions had no 'course' but 'active' languages (Taiwanese
  /// Hokkien was dropped: its progress rows stay in user.db, unused).
  void _read(Map j, {required bool onboarded}) {
    final active = (j['active'] as List?)?.cast<String>() ?? const [];
    course = courseById(j['course'] ?? active.firstWhere((l) => courses.any((c) => c.id == l), orElse: () => ''));
    this.onboarded = j['onboarded'] ?? onboarded;
    mistakes = List<String>.from(j['mistakes'] ?? []);
    _streak = j['streak'] ?? 0;
    _lastDay = j['lastDay'] ?? '';
    _newToday = j['newToday'] ?? 0;
    days = List<String>.from(j['days'] ?? [if (_lastDay.isNotEmpty) _lastDay]);
    dailyGoal = j['newPerDay'] ?? 10;
    pron = Pron.values.asNameMap()[j['pron']] ?? Pron.pinyin;
    toneColors = j['toneColors'] ?? true;
    hints = j['hints'] ?? true;
    speechRate = (j['speechRate'] as num?)?.toDouble() ?? 0.42;
    themeMode = ThemeMode.values.asNameMap()[j['themeMode']] ?? ThemeMode.system;
    dynamicColor = j['dynamicColor'] ?? true;
    seed = j['seed'] ?? 0;
  }

  static Future<Database> _openDict(String dir) async {
    final version = int.parse((await rootBundle.loadString('assets/dict.version')).trim());
    final file = File('$dir/dict.db');
    if (_userVersion(file) != version) {
      final data = await rootBundle.load('assets/dict.db');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    return sqlite3.open(file.path, mode: OpenMode.readOnly);
  }

  /// SQLite's user_version, read from the file header (bytes 60-63) without opening it.
  static int? _userVersion(File f) {
    if (!f.existsSync()) return null;
    final raf = f.openSync();
    try {
      raf.setPositionSync(60);
      final b = raf.readSync(4);
      return b.length == 4 ? ByteData.sublistView(b).getInt32(0) : null;
    } finally {
      raf.closeSync();
    }
  }

  /// One-time import of the SharedPreferences format 'db', from before user.db.
  Future<void> _migrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('db');
    final j = raw == null ? null : jsonDecode(raw) as Map;
    _read(j ?? const {}, onboarded: j != null);
    if (j != null) {
      _db.execute('BEGIN');
      (j['progress'] as Map? ?? {}).forEach(
        (k, p) => _db.execute('INSERT OR REPLACE INTO progress VALUES (?,?,?,?,?,?)', [k, ...p]),
      );
      final imported = (j['imported'] as List? ?? []).cast<Map>();
      for (final (i, w) in imported.indexed) {
        final lang = w['lang'] ?? 'hok';
        if (!_isBundled(lang, w['hanzi'])) {
          _db.execute('INSERT OR IGNORE INTO imported VALUES (?,?,?,?,?,?,?)', [
            lang,
            w['hanzi'],
            w['roman'] ?? '',
            w['zhuyin'] ?? '',
            w['fr'],
            w['tag'] ?? 'Assistant IA',
            -i,
          ]);
        }
      }
      _db.execute('COMMIT');
    }
    _saveMeta();
    for (final k in ['db', 'state_tw', 'state']) {
      prefs.remove(k);
    }
  }

  bool _isBundled(String lang, String hanzi) =>
      dict.select('SELECT 1 FROM words WHERE lang = ? AND hanzi = ?', [lang, hanzi]).isNotEmpty;

  void _loadDeck(String lang) {
    if (_decks.containsKey(lang)) return;
    final progress = {
      for (final r in _db.select('SELECT * FROM progress WHERE key >= ? AND key < ?', ['$lang:', '$lang;']))
        r['key']: r,
    };
    final deck = <Word>[];
    final seen = <String>{};
    for (final w in [
      for (final r in _db.select(
        'SELECT lang, hanzi, roman, zhuyin, fr, tag FROM imported WHERE lang = ? ORDER BY added DESC',
        [lang],
      ))
        Word.fromRow(r, imported: true), // imports first: learned next
      for (final r in dict.select('SELECT * FROM words WHERE lang = ? ORDER BY pos', [lang])) Word.fromRow(r),
    ]) {
      if (!seen.add(w.hanzi)) continue;
      final p = progress[w.key];
      if (p != null) {
        w
          ..ease = p['ease']
          ..interval = p['interval']
          ..reps = p['reps']
          ..lapses = p['lapses']
          ..due = p['due'] == null ? null : DateTime.fromMillisecondsSinceEpoch(p['due']);
      }
      deck.add(w);
      _byKey[w.key] = w;
    }
    _decks[lang] = deck;
  }

  /// Splits the deck into units and lessons: each tag (theme, level, or Claude's tag for
  /// imports) is cut into lessons of [lessonSize] words, and long ones into units of
  /// [lessonsPerUnit] lessons.
  void _refresh() {
    words = _decks[course.id]!;
    final groups = <String, List<Word>>{};
    for (final w in words) {
      (groups['${w.imported ? 'import' : 'deck'}:${w.tag}'] ??= []).add(w);
    }
    units = [];
    for (final group in groups.values) {
      final w = group.first;
      final lessons = [
        for (var i = 0; i < group.length; i += lessonSize) group.sublist(i, min(i + lessonSize, group.length)),
      ];
      if (lessons.length > 1 && lessons.last.length < lessonSize ~/ 2) {
        lessons[lessons.length - 2].addAll(lessons.removeLast());
      }
      final (section, title) = w.imported
          ? ('Vos mots de l’assistant IA', w.tag)
          : w.level == 0
          ? ('Les essentiels', w.tag)
          : ('Niveau ${w.tag}', w.tag.substring(w.tag.indexOf(' · ') + 3));
      final parts = (lessons.length / lessonsPerUnit).ceil();
      for (var p = 0; p < parts; p++) {
        final unit = Unit(section, title, part: p + 1, parts: parts);
        final chunk = lessons.skip(p * lessonsPerUnit).take(lessonsPerUnit);
        unit.lessons.addAll([for (final (i, l) in chunk.indexed) Lesson(unit, i + 1, l)]);
        units.add(unit);
      }
    }
    notifyListeners();
  }

  /// The first lesson with words left to learn.
  Lesson? get nextLesson {
    for (final u in units) {
      for (final l in u.lessons) {
        if (!l.done) return l;
      }
    }
    return null;
  }

  void setCourse(Course c) {
    _loadDeck(c.id);
    course = c;
    _saveMeta();
    _refresh();
  }

  /// Settings: [update] changes fields, then they're saved and the UI rebuilt.
  void set(VoidCallback update, {bool appearance = false}) {
    update();
    _saveMeta();
    if (appearance) this.appearance.value++;
    notifyListeners();
  }

  /// Adds words not already known, first in their deck so they're the next ones taught.
  int addWords(Iterable<Word> list) {
    var n = 0;
    for (final w in list) {
      if (_byKey.containsKey(w.key) || _isBundled(w.lang, w.hanzi)) continue;
      _db.execute('INSERT OR IGNORE INTO imported VALUES (?,?,?,?,?,?,?)', [
        w.lang,
        w.hanzi,
        w.roman,
        w.zhuyin,
        w.fr,
        w.tag,
        DateTime.now().microsecondsSinceEpoch,
      ]);
      if (_db.updatedRows == 0) continue;
      final word = Word(w.lang, w.hanzi, w.roman, w.fr, w.tag, zhuyin: w.zhuyin, imported: true);
      _decks[w.lang]?.insert(0, word);
      _byKey[w.key] = word;
      n++;
    }
    _refresh();
    return n;
  }

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);
  String get _today => _day(DateTime.now());

  int get streak =>
      _lastDay == _today || _lastDay == _day(DateTime.now().subtract(const Duration(days: 1))) ? _streak : 0;
  bool get activeToday => _lastDay == _today;
  int get learnedToday => activeToday ? _newToday : 0;

  Iterable<Word> get learned => words.where((w) => !w.isNew);

  List<Word> get due {
    final now = DateTime.now();
    return words.where((w) => !w.isNew && !w.due!.isAfter(now)).toList()..sort((a, b) => a.due!.compareTo(b.due!));
  }

  /// Reviewing ahead: the [n] learned words that come up soonest but aren't due yet.
  List<Word> ahead([int n = 20]) {
    final now = DateTime.now();
    return (words.where((w) => !w.isNew && w.due!.isAfter(now)).toList()..sort((a, b) => a.due!.compareTo(b.due!)))
        .take(n)
        .toList();
  }

  /// Reviews coming up on each of the next [n] days (index 0 = later today).
  List<int> forecast([int n = 7]) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List.filled(n, 0);
    for (final w in words) {
      if (w.isNew || !w.due!.isAfter(now)) continue;
      final d = DateTime(w.due!.year, w.due!.month, w.due!.day).difference(today).inDays;
      if (d < n) counts[d]++;
    }
    return counts;
  }

  Word? byKey(String key) => _byKey[key];

  final _examples = <String, List<Example>>{};

  /// Example sentences: the dictionary's picks for the word, else any containing it.
  List<Example> examples(Word w) => _examples[w.key] ??= () {
    var rows = dict.select(
      'SELECT s.hanzi, s.roman, s.fr FROM examples e JOIN sentences s ON s.id = e.sid '
      'WHERE e.lang = ? AND e.hanzi = ? ORDER BY e.n',
      [w.lang, w.hanzi],
    );
    if (rows.isEmpty) {
      rows = dict.select(
        'SELECT hanzi, roman, fr FROM sentences WHERE instr(hanzi, ?) > 0 ORDER BY length(hanzi) '
        'LIMIT 3',
        [w.hanzi],
      );
    }
    return [for (final r in rows) (hanzi: r['hanzi'] as String, roman: r['roman'] as String, fr: r['fr'] as String)];
  }();

  /// Review: the learner's own grade.
  void grade(Word w, Grade g) {
    _touchDay();
    if (w.isNew) _newToday++;
    applyGrade(w, g, DateTime.now());
    _db.execute('INSERT OR REPLACE INTO progress VALUES (?,?,?,?,?,?)', [
      w.key,
      w.ease,
      w.interval,
      w.reps,
      w.lapses,
      w.due?.millisecondsSinceEpoch,
    ]);
    if (g == Grade.again) _addMistake(w);
    _saveMeta();
    notifyListeners();
  }

  /// End of a lesson: the word goes into reviews, back sooner if it was missed.
  void learn(Word w, {bool stumbled = false}) => grade(w, stumbled ? Grade.hard : Grade.good);

  /// "I already know it": skipped in lessons, first review in a few days.
  void markKnown(Word w) => grade(w, Grade.easy);

  void quizAnswer(Word w, bool correct) {
    _touchDay();
    correct ? mistakes.remove(w.key) : _addMistake(w);
    _saveMeta();
    notifyListeners();
  }

  void _touchDay() {
    if (_lastDay == _today) return;
    _streak = streak + 1;
    _lastDay = _today;
    _newToday = 0;
    days = [...days.where((d) => d != _today), _today];
    if (days.length > 60) days = days.sublist(days.length - 60);
  }

  void _addMistake(Word w) {
    mistakes
      ..remove(w.key)
      ..insert(0, w.key);
    if (mistakes.length > 30) mistakes.removeLast();
  }

  void _saveMeta() => _db.execute("INSERT OR REPLACE INTO meta VALUES ('state', ?)", [
    jsonEncode({
      'course': course.id,
      'onboarded': onboarded,
      'mistakes': mistakes,
      'streak': _streak,
      'lastDay': _lastDay,
      'newToday': _newToday,
      'days': days,
      'newPerDay': dailyGoal,
      'pron': pron.name,
      'toneColors': toneColors,
      'hints': hints,
      'speechRate': speechRate,
      'themeMode': themeMode.name,
      'dynamicColor': dynamicColor,
      'seed': seed,
    }),
  ]);

  /// Extracts the first JSON array from a pasted Claude reply (code fences and prose
  /// around it are ignored). Entries without hanzi or fr are skipped, and so are entries
  /// in a language that isn't a course; lang defaults to [lang].
  static List<Word> parseDeck(String text, {required String lang}) {
    final s = text.indexOf('['), e = text.lastIndexOf(']');
    if (s < 0 || e < s) throw const FormatException('aucun tableau JSON trouvé');
    String str(Object? v) => v is String ? v : '';
    return [
      for (final m in (jsonDecode(text.substring(s, e + 1)) as List).whereType<Map>())
        if (m['hanzi'] is String && m['fr'] is String && (m['lang'] == null || courses.any((c) => c.id == m['lang'])))
          Word(
            m['lang'] ?? lang,
            m['hanzi'],
            str(m['roman'] ?? m['pinyin']),
            m['fr'],
            m['tag'] is String ? m['tag'] : 'Assistant IA',
            zhuyin: str(m['zhuyin']),
          ),
    ];
  }
}

final store = Store();
final messenger = GlobalKey<ScaffoldMessengerState>();
final tts = FlutterTts();

/// Speaks with the phone's voice for the course language.
Future<void> speak(String text, {bool slow = false}) async {
  try {
    // Set per call: flutter_tts resets the language to the system default when its engine
    // finishes initializing, so a setLanguage at startup ends up French.
    await tts.setLanguage(store.course.tts);
    await tts.setSpeechRate(slow ? store.speechRate * 0.55 : store.speechRate);
    if (await tts.speak(text) != 1) throw Exception();
  } catch (_) {
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Voix ${store.course.native} indisponible'),
          action: SnackBarAction(label: 'Réglages', onPressed: openTtsSettings),
        ),
      );
  }
}

Future<void> play(Word w, {bool slow = false}) => speak(w.hanzi, slow: slow);

/// Whether the phone has a voice for the course language installed.
Future<bool> voiceInstalled() async {
  try {
    final ok = await tts.isLanguageAvailable(store.course.tts);
    if (ok != true) return false;
    return Platform.isAndroid ? await tts.isLanguageInstalled(store.course.tts) == true : true;
  } catch (_) {
    return false;
  }
}

const android = MethodChannel('lllearner/android');

/// Android's text-to-speech settings, where voices are installed.
Future<void> openTtsSettings() => android.invokeMethod('openTtsSettings').catchError((_) => null);

/// Text in the course language, with its locale so the right glyph variants are used
/// (traditional, Taiwan forms).
TextStyle script(double size, {Color? color, FontWeight? weight}) =>
    TextStyle(fontSize: size, color: color, fontWeight: weight, locale: store.course.locale, height: 1.25);

const _tones = {
  'áàâāǎ': 'a',
  'éèêēěë': 'e',
  'íìîīǐï': 'i',
  'óòôōǒő': 'o',
  'úùûūǔüǖǘǚǜ': 'u',
  'ḿ': 'm',
  'ńǹň': 'n',
  'ç': 'c',
};

/// Lowercase without tone marks, accents or hyphens, for search ('xiexie' finds xièxie).
String plain(String s) {
  var r = s.toLowerCase();
  _tones.forEach((k, v) => k.split('').forEach((c) => r = r.replaceAll(c, v)));
  return r.replaceAll(RegExp("[\\u0300-\\u036f'’ -]"), '');
}
