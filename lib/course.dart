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
];

Course courseById(String id) => courses.firstWhere((c) => c.id == id, orElse: () => courses.first);
