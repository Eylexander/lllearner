import 'dart:math';

/// Every pinyin syllable (without tones), plus erhua 'r', the interjections m, n, ng, ê,
/// and the Taiwan reading yái (崖).
final _valid = {
  ...'a ai an ang ao ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu ca cai can cang cao ce cen ceng '
          'cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou '
          'cu cuan cui cun cuo da dai dan dang dao de dei den deng di dia dian diang diao die ding diu dong dou du duan '
          'dui dun duo e ei en eng er fa fan fang fei fen feng fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu '
          'gua guai guan guang gui gun guo ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun '
          'huo ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun ka kai kan kang kao ke kei ken keng kong kou '
          'ku kua kuai kuan kuang kui kun kuo la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo '
          'long lou lu luan lun luo lü lüe lün ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou '
          'mu na nai nan nang nao ne nei nen neng ni nia nian niang niao nie nin ning niu nong nou nu nuan nun nuo nü nüe '
          'o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu qi qia qian qiang qiao qie qin qing '
          'qiong qiu qu quan que qun r ran rang rao re ren reng ri rong rou ru ruan rui run ruo sa sai san sang sao se sei '
          'sen seng sha shai shan shang shao she shei shen sheng shi shong shou shu shua shuai shuan shuang shui shun shuo '
          'si song sou su suan sui sun suo ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun '
          'tuo wa wai wan wang wei wen weng wo wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ya yan '
          'yang yao ye yi yin ying yo yong you yu yuan yue yun za zai zan zang zao ze zei zen zeng zha zhai zhan zhang '
          'zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun '
          'zuo m n ng ê yai'
      .split(' '),
};

/// Toned vowels: [base][tone - 1].
const _toned = {'a': 'āáǎà', 'e': 'ēéěè', 'i': 'īíǐì', 'o': 'ōóǒò', 'u': 'ūúǔù', 'ü': 'ǖǘǚǜ'};

/// Toned letter → (toneless letter, tone).
final _base = {
  for (final MapEntry(key: b, value: ts) in _toned.entries)
    for (var i = 0; i < 4; i++) ts[i]: (b, i + 1),
  'ḿ': ('m', 2),
  'ń': ('n', 2),
  'ň': ('n', 3),
  'ǹ': ('n', 4),
};

bool _isMark(int c) => c >= 0x300 && c <= 0x36f;
const _combining = {0x304: 1, 0x301: 2, 0x30c: 3, 0x300: 4};

/// A piece of a pinyin string: a syllable with its tone (1-4, 5 = neutral), or the
/// text between syllables (spaces, apostrophes, punctuation) with tone 0.
typedef Syllable = ({String text, int tone});

/// Splits pinyin into syllables: 'Wǒ xǐhuan chá.' → Wǒ, ' ', xǐ, huan, ' ', chá, '.'.
/// Letters runs that aren't pinyin are kept whole, with tone 0.
List<Syllable> syllables(String roman) {
  final out = <Syllable>[];
  // Letters with their combining marks, vs. everything else.
  for (final m in RegExp(r"[\p{L}̀-ͯ]+|[^\p{L}̀-ͯ]+", unicode: true).allMatches(roman)) {
    final run = m[0]!;
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(run[0])) {
      out.add((text: run, tone: 0));
      continue;
    }
    final parts = _split(run);
    if (parts == null) {
      out.add((text: run, tone: 0));
    } else {
      out.addAll(parts);
    }
  }
  return out;
}

/// Tones of the syllables only: 'nǐhǎo' → [3, 3].
List<int> tones(String roman) => [
  for (final s in syllables(roman))
    if (s.tone > 0) s.tone,
];

/// One letter run into syllables, fewest first; a syllable starting with a vowel inside
/// a run costs extra, since pinyin would have written an apostrophe (fāngàn = fān-gàn).
List<Syllable>? _split(String run) {
  // Letters (with marks attached) as units, with their toneless lowercase form and tone.
  final units = <(String, String, int)>[];
  for (final r in run.runes) {
    final c = String.fromCharCode(r);
    if (_isMark(r)) {
      if (units.isEmpty) return null;
      final (text, plain, _) = units.removeLast();
      units.add((text + c, plain, _combining[r] ?? 0));
      continue;
    }
    final lower = c.toLowerCase();
    final (plain, tone) = _base[lower] ?? (lower == 'v' ? 'ü' : lower, 0);
    units.add((c, plain, tone));
  }
  final n = units.length;
  final cost = List<double>.filled(n + 1, double.infinity)..[0] = 0;
  final from = List<int>.filled(n + 1, -1);
  for (var i = 0; i < n; i++) {
    if (cost[i] == double.infinity) continue;
    var key = '';
    for (var j = i; j < n && j - i < 6; j++) {
      key += units[j].$2;
      if (!_valid.contains(key)) continue;
      final c = cost[i] + 1 + (i > 0 && 'aeoê'.contains(key[0]) ? 0.5 : 0);
      if (c < cost[j + 1]) {
        cost[j + 1] = c;
        from[j + 1] = i;
      }
    }
  }
  if (from[n] < 0) return null;
  final out = <Syllable>[];
  for (var j = n; j > 0; j = from[j]) {
    final part = units.sublist(from[j], j);
    final tone = part.map((u) => u.$3).firstWhere((t) => t > 0, orElse: () => 5);
    out.insert(0, (text: part.map((u) => u.$1).join(), tone: tone));
  }
  return out;
}

/// The syllable with another tone (1-4), or itself if it has no vowel to mark.
String retone(String syllable, int tone) {
  // Drop the current mark, then put the new one where pinyin puts it: a, e, o of ou,
  // else the last vowel.
  final plain = [
    for (final r in syllable.runes)
      if (!_isMark(r))
        switch (_base[String.fromCharCode(r).toLowerCase()]) {
          (final b, _) => String.fromCharCode(r) == String.fromCharCode(r).toLowerCase() ? b : b.toUpperCase(),
          null => String.fromCharCode(r),
        },
  ];
  final low = plain.join().toLowerCase();
  final i = low.contains('a')
      ? low.indexOf('a')
      : low.contains('e')
      ? low.indexOf('e')
      : low.contains('ou')
      ? low.indexOf('o')
      : [for (final v in 'iouü'.split('')) low.lastIndexOf(v)].reduce(max);
  if (i < 0) return syllable;
  final marked = _toned[plain[i].toLowerCase()]![tone - 1];
  plain[i] = plain[i] == plain[i].toLowerCase() ? marked : marked.toUpperCase();
  return plain.join();
}

/// Up to [n] distinct wrong-tone versions of [roman] (for tone exercises): one or two
/// toned syllables changed each time. Empty if the word has no tone to change.
List<String> toneVariants(String roman, int n, Random rng) {
  final parts = syllables(roman);
  final toned = [
    for (final (i, s) in parts.indexed)
      if (s.tone >= 1 && s.tone <= 4) i,
  ];
  if (toned.isEmpty) return const [];
  final out = <String>{};
  for (var tries = 0; out.length < n && tries < 60; tries++) {
    final changed = [...parts];
    final picks = (toned.toList()..shuffle(rng)).take(toned.length > 1 && rng.nextBool() ? 2 : 1);
    for (final i in picks) {
      final others = [1, 2, 3, 4]..remove(parts[i].tone);
      changed[i] = (text: retone(parts[i].text, others[rng.nextInt(3)]), tone: 0);
    }
    final s = changed.map((p) => p.text).join();
    if (s != roman) out.add(s);
  }
  return out.toList();
}
