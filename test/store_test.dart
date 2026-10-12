import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lllearner/exercise.dart';
import 'package:lllearner/pinyin.dart';
import 'package:lllearner/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String dir;
  final opened = <Store>[];
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lllearner').path;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    for (final s in opened) {
      s.close();
    }
    opened.clear();
    Directory(dir).deleteSync(recursive: true);
  });

  Future<Store> fresh() async {
    final s = Store();
    await s.load(dir: dir);
    opened.add(s);
    return s;
  }

  test('a fresh install starts with onboarding and the first lesson', () async {
    final s = await fresh();
    expect(s.onboarded, isFalse);
    expect(s.course.id, 'man');
    expect(s.words.length, greaterThan(6000));
    expect(s.units.first.section, 'Les essentiels');
    expect(s.units.first.title, 'Salutations');
    final first = s.nextLesson!;
    expect(first.words.first.hanzi, '你好');
    for (final l in s.units.expand((u) => u.lessons)) {
      expect(l.words.length, inInclusiveRange(3, Store.lessonSize + 2));
    }
    // Long levels are cut into units of at most 8 lessons.
    expect(s.units.firstWhere((u) => u.section == 'Niveau 1 · Débutant').name, 'Débutant · 1/7');
    expect(s.units.every((u) => u.lessons.length <= Store.lessonsPerUnit), isTrue);

    for (final w in first.words) {
      s.learn(w);
    }
    expect(first.done, isTrue);
    expect(s.nextLesson, isNot(first));
    expect(s.learned.length, first.words.length);
    expect(s.learnedToday, first.words.length);
    expect(s.due, isEmpty); // first review tomorrow
    expect(s.forecast()[1], first.words.length);
    expect(s.streak, 1);
  });

  test('state from before courses: Hokkien dropped, Mandarin progress kept', () async {
    sqlite3.open('$dir/user.db')
      ..execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)')
      ..execute(
        'CREATE TABLE progress(key TEXT PRIMARY KEY, ease REAL, interval REAL, reps INTEGER, lapses INTEGER, due INTEGER)',
      )
      ..execute("INSERT INTO meta VALUES ('state', ?)", [
        jsonEncode({
          'active': ['hok', 'man'],
          'mistakes': ['man:謝謝'],
          'streak': 3,
          'lastDay': '2026-01-01',
          'newToday': 2,
          'newPerDay': 20,
        }),
      ])
      ..execute("INSERT INTO progress VALUES ('man:謝謝', 2.5, 3, 2, 0, 0)")
      ..execute("INSERT INTO progress VALUES ('hok:多謝', 2.5, 3, 2, 0, 0)")
      ..close();
    final s = await fresh();
    expect(s.onboarded, isTrue);
    expect(s.course.id, 'man');
    expect(s.dailyGoal, 20);
    expect(s.byKey('man:謝謝')!.reps, 2);
    expect(s.byKey('hok:多謝'), isNull);
    expect(s.mistakes, ['man:謝謝']);
    expect(s.due.map((w) => w.key), ['man:謝謝']);
  });

  test('migrates the SharedPreferences store into SQLite, once', () async {
    SharedPreferences.setMockInitialValues({
      'db': jsonEncode({
        'active': ['man'],
        'progress': {
          'man:謝謝': [2.5, 3, 2, 0, 0],
        },
        'imported': [
          {'lang': 'man', 'hanzi': '鹹酥雞', 'roman': 'xiánsūjī', 'fr': 'Poulet frit', 'tag': 'Claude'},
          {'lang': 'man', 'hanzi': '謝謝', 'roman': 'xièxie', 'fr': 'Merci', 'tag': 'Claude'}, // bundled: dropped
        ],
        'newPerDay': 20,
      }),
    });
    final s = await fresh();
    expect(s.onboarded, isTrue);
    expect(s.words.first.key, 'man:鹹酥雞');
    expect(s.byKey('man:謝謝')!.reps, 2);
    expect(s.dailyGoal, 20);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);

    final again = await fresh();
    expect(again.byKey('man:謝謝')!.reps, 2);
    expect(again.byKey('man:鹹酥雞')!.imported, isTrue);
  });

  test('imports become the next lessons; settings persist', () async {
    final s = await fresh();
    expect(s.addWords([Word('man', '鹹酥雞', 'xiánsūjī', 'Poulet frit', 'Marché de nuit')]), 1);
    expect(s.addWords([Word('man', '謝謝', 'xièxie', 'Merci', 'Claude')]), 0); // already bundled
    expect(s.units.first.section, 'Vos mots de l’assistant IA');
    expect(s.units.first.title, 'Marché de nuit');
    expect(s.nextLesson!.words.single.hanzi, '鹹酥雞');
    s.set(() {
      s.onboarded = true;
      s.pron = Pron.both;
      s.dynamicColor = false;
      s.seed = 2;
    });
    s.grade(s.byKey('man:你好')!, Grade.good);

    final again = await fresh();
    expect(again.words.first.key, 'man:鹹酥雞');
    expect(again.byKey('man:你好')!.reps, 1);
    expect((again.onboarded, again.pron, again.dynamicColor, again.seed), (true, Pron.both, false, 2));
  });

  test('example sentences, chosen for the word or found by search', () async {
    final s = await fresh();
    final thanks = s.examples(s.byKey('man:謝謝')!);
    expect(thanks, isNotEmpty);
    expect(thanks.every((e) => e.hanzi.contains('謝謝') && e.roman.isNotEmpty && e.fr.isNotEmpty), isTrue);
    s.addWords([Word('man', '咖啡廳', 'kāfēitīng', 'Café (lieu)', 'Claude')]);
    for (final e in s.examples(s.byKey('man:咖啡廳')!)) {
      expect(e.hanzi, contains('咖啡廳'));
    }
  });

  test('exercises draw wrong answers from nearby or learned words only', () async {
    final s = await fresh();
    final lesson = s.nextLesson!;
    final pool = distractorPool(lesson.words, also: lesson.words);
    expect(pool.every((w) => w.level <= 1), isTrue); // no advanced vocabulary for a beginner
    final rng = Random(3);
    for (final w in lesson.words) {
      for (final k in Kind.values) {
        final ex = makeExercise(w, k, pool, rng);
        if (ex == null) continue;
        expect(ex.options, hasLength(4));
        expect(ex.options.where((o) => o.correct), hasLength(1));
        expect(ex.options.map((o) => o.text).toSet(), hasLength(4));
      }
    }
    // 你好 'Bonjour' and 早安 'Bonjour (le matin)' mean the same: never options together.
    final hello = s.byKey('man:你好')!;
    for (var i = 0; i < 30; i++) {
      final ex = makeExercise(hello, Kind.meaning, pool, rng)!;
      expect(ex.options.map((o) => o.word?.hanzi), isNot(contains('早安')));
    }
  });

  test('every word of the deck has pinyin the app can split into syllables', () async {
    final s = await fresh();
    final bad = [
      for (final w in s.words)
        if (syllables(w.roman).any((p) => p.tone == 0 && RegExp(r'\p{L}', unicode: true).hasMatch(p.text))) w.roman,
    ];
    expect(bad, isEmpty);
  });

  test('SRS intervals grow on success and reset on failure', () {
    final w = Word('man', '吃', 'chī', 'Manger', 'Verbes');
    applyGrade(w, Grade.good, DateTime(2026));
    expect(w.interval, 1);
    applyGrade(w, Grade.good, w.due!);
    expect(w.interval, 3);
    final now = w.due!;
    applyGrade(w, Grade.good, now);
    expect(w.interval, 7.5);
    expect(w.due, now.add(const Duration(hours: 180)));
    applyGrade(w, Grade.again, now);
    expect((w.interval, w.reps, w.lapses), (0, 0, 1));
    expect(w.due, now.add(const Duration(minutes: 1)));
  });

  test('SRS reviews ahead of time grow from the elapsed time', () {
    final now = DateTime(2026);
    final w = Word('man', '吃', 'chī', 'Manger', 'Verbes')
      ..reps = 3
      ..interval = 10
      ..due = now.add(const Duration(days: 8)); // last seen 2 days ago
    expect(nextInterval(w, Grade.good, now), 10); // not 25: kept, not inflated
    expect(nextInterval(w, Grade.hard, now), closeTo(2.4, 1e-9));
    w.due = now.add(const Duration(days: 1)); // 9 days elapsed
    expect(nextInterval(w, Grade.good, now), 22.5);
    w.due = now; // on time
    expect(nextInterval(w, Grade.good, now), 25);
  });

  test('parseDeck pulls the JSON array out of a Claude reply', () {
    final d = Store.parseDeck(
      'Voici tes mots :\n```json\n[{"lang":"man","hanzi":"市場","roman":"shìchǎng","fr":"marché"},'
      '{"hanzi":"捷運站","pinyin":"jiéyùn zhàn","fr":"station de métro","tag":"Ville"},'
      '{"lang":"hok","hanzi":"菜市仔","roman":"tshài-tshī-á","fr":"marché"},{"roman":"incomplet"}]\n```\nBonne révision !',
      lang: 'man',
    );
    expect(d.map((w) => w.key), ['man:市場', 'man:捷運站']); // no course for hok: skipped
    expect(d.last.roman, 'jiéyùn zhàn');
    expect(d.first.tag, 'Assistant IA');
    expect(() => Store.parseDeck('pas de json', lang: 'man'), throwsFormatException);
  });

  test('plain strips tones, accents, apostrophes and spaces for search', () {
    expect(plain("Zǎo'ān Métro"), 'zaoanmetro');
    expect(plain('nǚ xièxie'), 'nuxiexie');
  });
}
