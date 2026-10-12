import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lllearner/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lllearner').path);
  tearDown(() => Directory(dir).deleteSync(recursive: true));

  test('migrates the SharedPreferences store into SQLite, once', () async {
    SharedPreferences.setMockInitialValues({
      'db': jsonEncode({
        'active': ['hok', 'man'],
        'progress': {
          'hok:多謝': [2.5, 3, 2, 0, 0],
        },
        'imported': [
          {'lang': 'hok', 'hanzi': '珍珠奶茶', 'roman': 'tsin-tsu-ling-tê', 'fr': 'Bubble tea', 'tag': 'Claude'},
          {'lang': 'hok', 'hanzi': '多謝', 'roman': 'to-siā', 'fr': 'Merci', 'tag': 'Claude'}, // bundled: dropped
        ],
        'mistakes': ['hok:多謝'],
        'newPerDay': 20,
      }),
    });
    final s = Store();
    await s.load(dir: dir);
    expect(s.active, {'hok', 'man'});
    expect(s.words.first.key, 'hok:珍珠奶茶');
    expect(s.byKey('hok:多謝')!.reps, 2);
    expect(s.byKey('hok:多謝')!.see, '謝謝 xièxie');
    expect(s.mistakes, ['hok:多謝']);
    expect(s.newPerDay, 20);
    expect(s.words.map((w) => w.key).toSet().length, s.words.length);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);

    final again = Store();
    await again.load(dir: dir);
    expect(again.byKey('hok:多謝')!.reps, 2);
    expect(again.byKey('hok:珍珠奶茶'), isNotNull);
  });

  test('migrates the older Hokkien-only state', () async {
    SharedPreferences.setMockInitialValues({
      'state_tw': jsonEncode({
        'words': [
          {
            'hanzi': '多謝',
            'tailo': 'to-siā',
            'fr': 'Merci',
            'ease': 2.5,
            'interval': 3,
            'reps': 2,
            'lapses': 0,
            'due': 0,
          },
        ],
        'mistakes': ['多謝'],
      }),
    });
    final s = Store();
    await s.load(dir: dir);
    expect(s.byKey('hok:多謝')!.reps, 2);
    expect(s.mistakes, ['hok:多謝']);
  });

  test('grades persist per row; languages interleave; dictionary details', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.load(dir: dir);
    s.setActive({'hok', 'man'});
    expect(s.byKey('hok:學生'), isNotNull);
    expect(s.byKey('man:學生'), isNotNull);
    expect(s.sessionQueue().take(4).map((w) => w.lang), ['hok', 'man', 'hok', 'man']);
    // Lexique order: mixed level by level, not one whole deck after the other.
    final level1 = s.words.where((w) => w.tag.startsWith('1 ·')).take(4).map((w) => w.lang);
    expect(level1, ['hok', 'man', 'hok', 'man']);
    expect(
      s.words.indexWhere((w) => w.tag.startsWith('7 ·')),
      greaterThan(s.words.lastIndexWhere((w) => w.lang == 'man')),
    );
    expect(s.words.where((w) => w.lang == 'hok').length, greaterThan(15000));

    s.grade(s.byKey('man:謝謝')!, Grade.good);
    expect(s.addWords([Word('hok', '珍珠奶茶', 'tsin-tsu-ling-tê', 'Bubble tea', 'Claude')]), 1);
    expect(s.addWords([Word('hok', '多謝', 'to-siā', 'Merci', 'Claude')]), 0); // already bundled

    final again = Store();
    await again.load(dir: dir);
    expect(again.active, {'hok', 'man'});
    expect(again.byKey('man:謝謝')!.reps, 1);
    expect(again.words.first.key, 'hok:珍珠奶茶');

    final eat = again.byKey('hok:食')!;
    expect(again.definitions(eat), startsWith('1. (動詞) 吃。'));
    final hello = again.byKey('hok:你食飽未？')!;
    expect(hello.moe, 0); // hand-written phrase: no dictionary entry
    final notYet = again.words.firstWhere((w) => w.moe == 1653);
    expect(again.examples(notYet).map((e) => e.hanji), contains('你食飽未？'));
    final dictOnly = again.words.firstWhere((w) => w.fr.isEmpty);
    expect(dictOnly.meaning, startsWith('華語：'));
  });

  test('SRS intervals grow on success and reset on failure', () {
    final now = DateTime(2026);
    final w = Word('hok', '食', 'tsia̍h', 'Manger', 'Verbes');
    applyGrade(w, Grade.good, now);
    expect(w.interval, 1);
    applyGrade(w, Grade.good, now);
    expect(w.interval, 3);
    applyGrade(w, Grade.good, now);
    expect(w.interval, 7.5);
    expect(w.due, now.add(const Duration(hours: 180)));
    applyGrade(w, Grade.again, now);
    expect((w.interval, w.reps, w.lapses), (0, 0, 1));
    expect(w.due, now.add(const Duration(minutes: 1)));
  });

  test('parseDeck pulls the JSON array out of a Claude reply', () {
    final d = Store.parseDeck(
      'Voici tes mots :\n```json\n[{"lang":"man","hanzi":"市場","roman":"shìchǎng","fr":"marché"},'
      '{"hanji":"菜市仔","tailo":"tshài-tshī-á","fr":"marché"},{"roman":"incomplet"}]\n```\nBonne révision !',
    );
    expect(d.map((w) => w.key), ['man:市場', 'hok:菜市仔']);
    expect(d.last.roman, 'tshài-tshī-á');
    expect(d.first.tag, 'Claude');
    expect(() => Store.parseDeck('pas de json'), throwsFormatException);
  });

  test('plain strips Tâi-lô and pinyin tones, accents and hyphens for search', () {
    expect(plain('Tsia̍h-pá Métro'), 'tsiahpa metro');
    expect(plain('nǚ to-siā'), 'nu tosia');
  });
}
