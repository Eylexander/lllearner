import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:sqlite3/sqlite3.dart' as sql show Row;

/// Languages spoken in Taipei, each a deck of assets/dict.db with its own progress.
const langs = {'hok': '台語', 'man': '華語'};
const langNames = {'hok': 'Taïwanais', 'man': 'Mandarin'};

/// A word of one deck: Han characters, romanization (Tâi-lô for hok, pinyin for man),
/// French gloss, and [see], its equivalent in the other language ("謝謝 xièxie").
class Word {
  Word(
    this.lang,
    this.hanzi,
    this.roman,
    this.fr,
    this.tag, {
    this.zhuyin = '',
    this.audio = '',
    this.see = '',
    this.moe = 0,
    this.short = '',
  });

  final String lang, hanzi, roman, zhuyin, fr, tag;
  final String audio; // hok: MOE recording path ('subak/5/5790'), '' if none
  final String see;
  final int moe; // MOE dictionary entry id (definitions, examples), 0 if none
  final String short; // first Mandarin definition, stands in when fr is ''
  double ease = 2.5;
  double interval = 0; // days
  int reps = 0, lapses = 0;
  DateTime? due; // null = never studied
  late final String searchKey = plain('$roman $zhuyin $fr $short $tag ${langNames[lang]}');

  String get key => '$lang:$hanzi';
  String get meaning => fr.isNotEmpty ? fr : '華語：$short';
  bool get isNew => due == null;
  bool get mastered => interval >= 21;
  bool get hasAudio => lang == 'man' || audio.isNotEmpty; // man: TTS

  factory Word.fromRow(sql.Row r) => Word(
    r['lang'],
    r['hanzi'],
    r['roman'],
    r['fr'],
    r['tag'],
    zhuyin: r['zhuyin'] ?? '',
    audio: r['audio'] ?? '',
    see: r['see'] ?? '',
    moe: r['moe'] ?? 0,
    short: r['short'] ?? '',
  );
}

enum Grade { again, hard, good, easy }

/// Next interval in days (simplified SM-2).
double nextInterval(Word w, Grade g) {
  final good = w.reps == 0
      ? 1.0
      : w.reps == 1
      ? 3.0
      : w.interval * w.ease;
  return switch (g) {
    Grade.again => 0.0,
    Grade.hard => w.reps == 0 ? 0.25 : max(1.0, w.interval * 1.2),
    Grade.good => good,
    Grade.easy => max(4.0, good * 1.3),
  };
}

void applyGrade(Word w, Grade g, DateTime now) {
  final next = nextInterval(w, g);
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

typedef Example = ({String hanji, String roman, String zh});

/// Two SQLite databases in the app support dir:
/// - dict.db: read-only copy of assets/dict.db (words, definitions, examples), recopied
///   when assets/dict.version changes;
/// - user.db: progress(key, …) one row per studied word, imported (words from Claude),
///   meta('state' → JSON: active languages, mistakes, streak and daily counters).
/// Decks of active languages are held in memory; definitions and examples are queried
/// on demand.
class Store extends ChangeNotifier {
  late final Database dict, _db;
  int newPerDay = 10;
  Set<String> active = {'hok'};
  final Map<String, List<Word>> _decks = {};
  final Map<String, Word> _byKey = {};
  List<Word> words = []; // active decks, in study order
  List<String> mistakes = []; // keys, most recent first
  int _streak = 0, _newToday = 0;
  String _lastDay = '';

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
      final j = jsonDecode(state['v']) as Map;
      active = Set<String>.from(j['active']);
      mistakes = List<String>.from(j['mistakes']);
      _streak = j['streak'];
      _lastDay = j['lastDay'];
      _newToday = j['newToday'];
      newPerDay = j['newPerDay'];
    }
    active.forEach(_loadDeck);
    _refresh();
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

  /// One-time import of the SharedPreferences formats: 'db' (two languages) or the
  /// Hokkien-only 'state_tw'.
  Future<void> _migrate() async {
    final prefs = await SharedPreferences.getInstance();
    var j = prefs.getString('db') == null ? null : jsonDecode(prefs.getString('db')!) as Map;
    final old = prefs.getString('state_tw');
    if (j == null && old != null) {
      final o = jsonDecode(old) as Map;
      j = {
        ...o,
        'active': ['hok'],
        'mistakes': [for (final h in o['mistakes'] ?? []) 'hok:$h'],
        'progress': {
          for (final w in o['words'])
            if (w['due'] != null) 'hok:${w['hanzi']}': [w['ease'], w['interval'], w['reps'], w['lapses'], w['due']],
        },
        'imported': [
          for (final w in o['words'])
            {'lang': 'hok', 'hanzi': w['hanzi'], 'roman': w['tailo'], 'fr': w['fr'], 'tag': w['tag']},
        ],
      };
    }
    if (j != null) {
      active = Set<String>.from(j['active'] ?? ['hok']);
      mistakes = List<String>.from(j['mistakes'] ?? []);
      _streak = j['streak'] ?? 0;
      _lastDay = j['lastDay'] ?? '';
      _newToday = j['newToday'] ?? 0;
      newPerDay = j['newPerDay'] ?? 10;
      _db.execute('BEGIN');
      (j['progress'] as Map? ?? {}).forEach(
        (k, p) => _db.execute('INSERT OR REPLACE INTO progress VALUES (?,?,?,?,?,?)', [k, ...p]),
      );
      final imported = (j['imported'] as List? ?? []).cast<Map>();
      for (final (i, w) in imported.indexed) {
        if (!_isBundled(w['lang'] ?? 'hok', w['hanzi'])) {
          _db.execute('INSERT OR IGNORE INTO imported VALUES (?,?,?,?,?,?,?)', [
            w['lang'] ?? 'hok',
            w['hanzi'],
            w['roman'] ?? '',
            w['zhuyin'] ?? '',
            w['fr'],
            w['tag'] ?? 'Claude',
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
        "SELECT lang, hanzi, roman, zhuyin, fr, tag, '' AS audio, '' AS see, 0 AS moe, '' AS short "
        'FROM imported WHERE lang = ? ORDER BY added DESC',
        [lang],
      ))
        Word.fromRow(r), // imports first: studied next
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

  /// Active decks mixed level by level ('3 · Élémentaire' → 3; essentials and imports
  /// → 0), alternating languages within a level, so both progress side by side.
  void _refresh() {
    final decks = [
      for (final l in langs.keys)
        if (active.contains(l)) _decks[l]!,
    ];
    final byLevel = [
      for (final d in decks) [for (var lv = 0; lv <= 7; lv++) d.where((w) => _level(w) == lv).toList()],
    ];
    words = [
      for (var lv = 0; lv <= 7; lv++)
        for (var i = 0; i < byLevel.map((d) => d[lv].length).fold(0, max); i++)
          for (final d in byLevel)
            if (i < d[lv].length) d[lv][i],
    ];
    notifyListeners();
  }

  static int _level(Word w) => int.tryParse(w.tag.split(' ').first)?.clamp(0, 7) ?? 0;

  void setActive(Set<String> langs) {
    if (langs.isEmpty) return;
    langs.forEach(_loadDeck);
    active = langs;
    _saveMeta();
    _refresh();
  }

  void setNewPerDay(int n) {
    newPerDay = n;
    _saveMeta();
    notifyListeners();
  }

  /// Adds words not already known, first in their deck so they're the next new cards.
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
      _decks[w.lang]?.insert(0, w);
      _byKey[w.key] = w;
      n++;
    }
    _refresh();
    return n;
  }

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);
  String get _today => _day(DateTime.now());

  int get streak =>
      _lastDay == _today || _lastDay == _day(DateTime.now().subtract(const Duration(days: 1))) ? _streak : 0;
  int get newLeftToday => _lastDay == _today ? max(0, newPerDay - _newToday) : newPerDay;

  List<Word> get due {
    final now = DateTime.now();
    return words.where((w) => !w.isNew && !w.due!.isAfter(now)).toList()..sort((a, b) => a.due!.compareTo(b.due!));
  }

  /// Due cards, then today's new cards (in [words] order, so languages alternate).
  List<Word> sessionQueue() => [...due, ...words.where((w) => w.isNew).take(newLeftToday)];

  Word? byKey(String key) => _byKey[key];

  /// MOE definitions ("1. (動詞) 吃。\n2. …"), '' for words outside the dictionary.
  String definitions(Word w) =>
      w.moe == 0 ? '' : dict.select('SELECT text FROM defs WHERE moe = ?', [w.moe]).firstOrNull?['text'] ?? '';

  List<Example> examples(Word w) => w.moe == 0
      ? const []
      : [
          for (final r in dict.select('SELECT hanji, roman, zh FROM examples WHERE moe = ? ORDER BY n', [w.moe]))
            (hanji: r['hanji'] as String, roman: r['roman'] as String, zh: r['zh'] as String),
        ];

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

  void quizAnswer(Word w, bool correct) {
    _touchDay();
    if (!correct) _addMistake(w);
    _saveMeta();
    notifyListeners();
  }

  void _touchDay() {
    if (_lastDay == _today) return;
    _streak = streak + 1;
    _lastDay = _today;
    _newToday = 0;
  }

  void _addMistake(Word w) {
    mistakes
      ..remove(w.key)
      ..insert(0, w.key);
    if (mistakes.length > 30) mistakes.removeLast();
  }

  void _saveMeta() => _db.execute("INSERT OR REPLACE INTO meta VALUES ('state', ?)", [
    jsonEncode({
      'active': active.toList(),
      'mistakes': mistakes,
      'streak': _streak,
      'lastDay': _lastDay,
      'newToday': _newToday,
      'newPerDay': newPerDay,
    }),
  ]);

  /// Extracts the first JSON array from a pasted Claude reply (code fences and prose
  /// around it are ignored). Entries without hanzi or fr are skipped; lang defaults to hok.
  static List<Word> parseDeck(String text) {
    final s = text.indexOf('['), e = text.lastIndexOf(']');
    if (s < 0 || e < s) throw const FormatException('aucun tableau JSON trouvé');
    String str(Object? v) => v is String ? v : '';
    return [
      for (final m in (jsonDecode(text.substring(s, e + 1)) as List).whereType<Map>())
        if ((m['hanzi'] ?? m['hanji']) is String && m['fr'] is String)
          Word(
            langs.containsKey(m['lang']) ? m['lang'] : 'hok',
            m['hanzi'] ?? m['hanji'],
            str(m['roman'] ?? m['tailo'] ?? m['pinyin']),
            m['fr'],
            m['tag'] is String ? m['tag'] : 'Claude',
            zhuyin: str(m['zhuyin']),
          ),
    ];
  }
}

final store = Store();
final messenger = GlobalKey<ScaffoldMessengerState>();
final _player = AudioPlayer();
final tts = FlutterTts();
const _moe = 'https://sutian.moe.edu.tw';

/// Mandarin: the phone's zh-TW TTS voice. Taiwanese has no TTS voice, so hok plays the
/// MOE dictionary recording (native speaker); hok words without one are silent.
Future<void> play(Word w) async {
  if (w.lang == 'man') {
    // Set per call: flutter_tts resets the language to the system default when its engine
    // finishes initializing, so a setLanguage at startup ends up French.
    await tts.setLanguage('zh-TW');
    await tts.speak(w.hanzi);
  } else if (w.audio.isNotEmpty) {
    await _playMoe(w.audio);
  }
}

final _exampleAudio = <int, List<String>>{};

/// Example recordings aren't in the dictionary export: the word's page lists them in
/// example order (verified on su/1653), so it is fetched once per word when needed.
// ponytail: scrapes sutian's HTML; if the page layout changes, example audio fails (words still play).
Future<void> playExample(Word w, int index) async {
  try {
    final paths = _exampleAudio[w.moe] ??= RegExp(r'/media/senn/mp3/imtong/(leku/\d+/\d+)\.mp3')
        .allMatches(await _get('$_moe/zh-hant/su/${w.moe}/').then(utf8.decode))
        .map((m) => m[1]!)
        .toSet()
        .toList();
    await _playMoe(paths[index]);
  } catch (_) {
    _audioError();
  }
}

/// Downloads hok recordings in the background so they play instantly: sutian is in Taiwan,
/// so a download takes 2-4 s on mobile.
void prefetch(Iterable<Word> words) {
  for (final w in words) {
    if (w.lang == 'hok' && w.audio.isNotEmpty) _moeFile(w.audio).ignore();
  }
}

Future<void> _playMoe(String path) async {
  try {
    await _player.play(DeviceFileSource((await _moeFile(path)).path));
  } catch (_) {
    _audioError();
  }
}

final _downloads = <String, Future<File>>{};

/// A MOE recording from the app cache, downloaded once. Concurrent requests share one download.
Future<File> _moeFile(String path) => _downloads[path] ??= () async {
  try {
    final file = File('${(await getApplicationCacheDirectory()).path}/audio/${path.replaceAll('/', '_')}.mp3');
    if (!file.existsSync()) {
      final part = File('${file.path}.part'); // renamed when complete, so no truncated cache
      await part.create(recursive: true);
      await part.writeAsBytes(await _get('$_moe/media/senn/mp3/imtong/$path.mp3'));
      await part.rename(file.path);
    }
    return file;
  } catch (_) {
    _downloads.remove(path); // retry on the next tap
    rethrow;
  }
}();

final _http = HttpClient(); // shared, so keep-alive skips the TLS handshake after the first download

Future<List<int>> _get(String url) async {
  final res = await (await _http.getUrl(Uri.parse(url))).close();
  if (res.statusCode != 200) throw HttpException('${res.statusCode}');
  return [for (final chunk in await res.toList()) ...chunk];
}

void _audioError() => messenger.currentState?.showSnackBar(
  const SnackBar(content: Text('Audio indisponible (connexion internet ?)'), behavior: SnackBarBehavior.floating),
);

/// Chinese text with the zh-TW locale so traditional glyph variants are used.
TextStyle zh(double size, {Color? color, FontWeight? weight}) =>
    TextStyle(fontSize: size, color: color, fontWeight: weight, locale: const Locale('zh', 'TW'), height: 1.2);

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

/// Lowercase without tone marks, accents or hyphens, for search ('tsiah' finds tsia̍h).
String plain(String s) {
  var r = s.toLowerCase();
  _tones.forEach((k, v) => k.split('').forEach((c) => r = r.replaceAll(c, v)));
  return r.replaceAll(RegExp('[\\u0300-\\u036f-]'), '');
}
