import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lllearner/pinyin.dart';

void main() {
  List<String> texts(String s) => [for (final p in syllables(s)) p.text];

  test('splits pinyin into syllables with their tones', () {
    expect(texts('nǐ hǎo'), ['nǐ', ' ', 'hǎo']);
    expect(tones('nǐ hǎo'), [3, 3]);
    expect(texts('xièxie'), ['xiè', 'xie']);
    expect(tones('xièxie'), [4, 5]);
    expect(texts('péngyǒu'), ['péng', 'yǒu']);
    expect(texts("zǎo'ān"), ['zǎo', "'", 'ān']);
    expect(texts('Zhōngwén'), ['Zhōng', 'wén']);
    expect(texts('xiǎolóngbāo'), ['xiǎo', 'lóng', 'bāo']);
    expect(tones('nǚrén'), [3, 2]);
    expect(texts('yìdiǎnr'), ['yì', 'diǎn', 'r']);
    // Without an apostrophe, a vowel can't start a syllable inside a word: fān-gàn.
    expect(texts('fāngàn'), ['fān', 'gàn']);
    // Sentences keep punctuation between syllables.
    expect(tones('Wǒ xǐhuan chá.'), [3, 3, 5, 2]);
    expect(syllables('Wǒ xǐhuan chá.').last, (text: '.', tone: 0));
    // Not pinyin: kept whole, untoned.
    expect(syllables('Muiriel'), [(text: 'Muiriel', tone: 0)]);
  });

  test('retone moves the mark where pinyin puts it', () {
    expect(retone('hǎo', 4), 'hào');
    expect(retone('xie', 2), 'xié');
    expect(retone('dōu', 3), 'dǒu');
    expect(retone('guì', 1), 'guī');
    expect(retone('lǜ', 2), 'lǘ');
    expect(retone('Wǒ', 4), 'Wò');
  });

  test('tone variants are distinct, differ from the answer, keep the letters', () {
    final rng = Random(1);
    for (final word in ['nǐ hǎo', 'xièxie', 'mā', 'zhēnzhū nǎichá']) {
      final v = toneVariants(word, 3, rng);
      expect(v, hasLength(3));
      expect(v.toSet(), hasLength(3));
      expect(v, isNot(contains(word)));
      for (final s in v) {
        expect(tones(s).length, tones(word).length);
      }
    }
    expect(toneVariants('ma', 3, rng), isEmpty); // neutral tone only
  });
}
