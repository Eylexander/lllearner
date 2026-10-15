import 'package:flutter/widgets.dart';

/// A course: one language taught to a French speaker. Its words are the deck of
/// assets/dict.db whose `lang` is [id] (built by tool/build_words.py), and its
/// progress rows are keyed '[id]:hanzi'. Adding a language = a deck + an entry in
/// [courses]; the rest of the app reads everything language-specific from here.
class Course {
  const Course({
    required this.id,
    required this.name,
    required this.native,
    required this.badge,
    required this.tagline,
    required this.tts,
    required this.voice,
    required this.locale,
    required this.romanization,
    required this.hasZhuyin,
    required this.hasTones,
    required this.hasCharacters,
    required this.writing,
    required this.region,
    required this.bravo,
    required this.sources,
    required this.claude,
    required this.greetings,
    required this.scenarios,
    required this.sentenceHint,
    this.tips = const [],
  });

  final String id;
  final String name; // 'Mandarin de Taïwan'
  final String native; // '華語'
  final String badge; // one character for the course avatar
  final String tagline;
  final String tts; // TTS voice locale
  final String voice; // its name in Android's TTS settings
  final Locale locale; // for glyph variants (traditional, Taiwan forms)
  final String romanization; // 'pinyin'
  final bool hasZhuyin;
  final bool hasTones; // tone colors and tone exercises
  final bool hasCharacters; // Chinese characters, taken apart from dict.db's chars table
  final String writing; // 'caractères', in prompts and labels
  final String region; // 'à Taïwan': where the language should sound natural
  final String bravo; // a cheer in the language, after a good quiz or the whole course
  final String sources; // the deck's credits, under the lexicon (required by their licenses)

  /// How Claude should name and write the language in prompts.
  final String claude;

  /// Morning, afternoon, evening: (characters, romanization, French).
  final List<(String, String, String)> greetings;

  /// Role-play situations for Claude: label → where the conversation happens.
  final Map<String, String> scenarios;
  final String sentenceHint; // example for "correct my sentence"

  /// Shown before the first lesson's words: how the language works.
  final List<Tip> tips;
}

/// A short explanation with examples the learner can listen to.
class Tip {
  const Tip(this.title, this.body, this.examples);
  final String title, body;
  final List<({String hanzi, String roman, String fr, String note})> examples;
}

const courses = [
  Course(
    id: 'man',
    name: 'Mandarin de Taïwan',
    native: '華語',
    badge: '華',
    tagline: 'Caractères traditionnels, pinyin et zhuyin, vocabulaire de Taipei',
    tts: 'zh-TW',
    voice: 'Chinois (Taïwan)',
    locale: Locale('zh', 'TW'),
    romanization: 'pinyin',
    hasZhuyin: true,
    hasTones: true,
    hasCharacters: true,
    writing: 'caractères',
    region: 'à Taïwan',
    bravo: '太棒了！',
    sources:
        'listes TOCFL · traductions CFDICT (CC BY-SA 3.0, chine-informations.com) · exemples Tatoeba '
        '(CC BY 2.0 FR, tatoeba.org) · caractères Make Me a Hanzi (LGPL 3, '
        'github.com/skishore/makemeahanzi)',
    claude:
        'le mandarin de Taïwan (華語 : caractères traditionnels, pinyin avec tons et zhuyin, '
        'vocabulaire et prononciation de Taïwan, pas de Chine continentale)',
    greetings: [('早安', 'zǎo’ān', 'Bonjour'), ('午安', 'wǔ’ān', 'Bon après-midi'), ('晚安', 'wǎn’ān', 'Bonsoir')],
    scenarios: {
      'Marché de nuit': 'au marché de nuit (je commande à manger)',
      'Boutique de thé': 'dans une boutique de bubble tea (je commande, sucre et glaçons)',
      'Métro': 'dans le métro de Taipei (je demande mon chemin)',
      'Restaurant': 'au restaurant (je commande et je paie)',
      'Rencontre': 'avec un(e) nouvel(le) ami(e) taïwanais(e) (on se présente)',
      'Médecin': 'chez le médecin (j’explique ce qui ne va pas)',
    },
    sentenceHint: '我想喝珍珠奶茶 / wǒ xiǎng hē zhēnzhū nǎichá',
    tips: [
      Tip(
        'Les quatre tons',
        'En mandarin, la mélodie de chaque syllabe change le sens du mot. Dans l’app, chaque ton a sa couleur, '
            'sur le pinyin comme sur les caractères. Touchez un exemple pour l’écouter.',
        [
          (hanzi: '媽', roman: 'mā', fr: 'maman', note: '1er ton : haut et plat'),
          (hanzi: '麻', roman: 'má', fr: 'chanvre', note: '2e ton : montant, comme « hein ? »'),
          (hanzi: '馬', roman: 'mǎ', fr: 'cheval', note: '3e ton : bas, descend puis remonte'),
          (hanzi: '罵', roman: 'mà', fr: 'gronder', note: '4e ton : tombe d’un coup, comme « Non ! »'),
          (hanzi: '嗎', roman: 'ma', fr: '(question)', note: 'ton neutre : court et léger'),
        ],
      ),
    ],
  ),
  Course(
    id: 'kor',
    name: 'Coréen',
    native: '한국어',
    badge: '한',
    tagline: 'Hangeul, romanisation officielle, coréen standard de Séoul',
    tts: 'ko-KR',
    voice: 'Coréen (Corée du Sud)',
    locale: Locale('ko', 'KR'),
    romanization: 'romanisation',
    hasZhuyin: false,
    hasTones: false,
    hasCharacters: false,
    writing: 'hangeul',
    region: 'en Corée',
    bravo: '잘했어요!',
    sources:
        'mots et traductions adaptés du 한국어기초사전, Institut national de la langue coréenne '
        '(CC BY-SA 2.0 KR, krdict.korean.go.kr) · exemples Tatoeba (CC BY 2.0 FR, tatoeba.org)',
    claude:
        'le coréen (한국어 : hangeul, romanisation révisée officielle, coréen standard de Séoul, '
        'style poli en -요 par défaut)',
    greetings: [
      ('좋은 아침이에요', 'joeun achimieyo', 'Bonjour (le matin)'),
      ('안녕하세요', 'annyeonghaseyo', 'Bonjour'),
      ('안녕하세요', 'annyeonghaseyo', 'Bonsoir'),
    ],
    scenarios: {
      'Restaurant': 'au restaurant coréen (je commande et je paie)',
      'Café': 'dans un café de Séoul (je commande à boire)',
      'Métro': 'dans le métro de Séoul (je demande mon chemin)',
      'Supérette': 'dans une supérette (j’achète et je paie)',
      'Rencontre': 'avec un(e) nouvel(le) ami(e) coréen(ne) (on se présente)',
      'Médecin': 'chez le médecin (j’explique ce qui ne va pas)',
    },
    sentenceHint: '저는 커피를 좋아해요 / jeoneun keopireul joahaeyo',
    tips: [
      Tip(
        'Le hangeul',
        'Le coréen s’écrit en hangeul, un alphabet : chaque bloc est une syllabe, faite d’une consonne, '
            'd’une voyelle et parfois d’une consonne finale (en bas). Un ㅇ au début est muet. Les mots se '
            'prononcent liés, d’où une romanisation qui suit le son (한국어 hangugeo). Touchez un exemple pour '
            'l’écouter.',
        [
          (hanzi: '나', roman: 'na', fr: 'moi', note: 'ㄴ n + ㅏ a'),
          (hanzi: '물', roman: 'mul', fr: 'eau', note: 'ㅁ m + ㅜ u + ㄹ l'),
          (hanzi: '밥', roman: 'bap', fr: 'riz cuit', note: 'ㅂ b + ㅏ a + ㅂ p (en finale)'),
          (hanzi: '오', roman: 'o', fr: 'cinq', note: 'ㅇ muet + ㅗ o'),
          (hanzi: '한', roman: 'han', fr: 'un (devant un nom)', note: 'ㅎ h + ㅏ a + ㄴ n'),
        ],
      ),
      Tip(
        'Parler poliment',
        'Avec un inconnu, on finit ses phrases par -요 : 먹어요 « je mange », 가요 « je vais ». Le lexique donne '
            'les verbes sous leur forme du dictionnaire, en -다 (먹다 « manger ») : les premières leçons '
            'montrent les formes polies les plus utiles.',
        [
          (hanzi: '요', roman: 'yo', fr: '(politesse)', note: 'fin des phrases polies'),
          (hanzi: '네', roman: 'ne', fr: 'oui', note: 'poli'),
          (hanzi: '다', roman: 'da', fr: '(dictionnaire)', note: 'fin des verbes au lexique'),
        ],
      ),
    ],
  ),
];

Course courseById(String id) => courses.firstWhere((c) => c.id == id, orElse: () => courses.first);
