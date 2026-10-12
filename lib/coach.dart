import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';

// The Claude bridge: no API (the user wants their subscription, which third-party
// apps can't use). `openClaude` (MainActivity.kt) opens the Claude app directly
// with a prefilled prompt carrying the learner profile; Claude's replies come back
// through the Android share menu ("sharedText") or by pasting, then `importDeck`.
const claude = MethodChannel('lllearner/claude');

/// Imports the vocabulary JSON from a Claude reply; returns a user-facing message.
String importDeck(String text) {
  try {
    final list = Store.parseDeck(text);
    final n = store.addWords(list);
    return list.isEmpty
        ? 'Aucun mot valide trouvé'
        : '$n mot(s) ajouté(s)${list.length > n ? ', ${list.length - n} déjà connu(s)' : ''}';
  } catch (_) {
    return 'Aucun bloc de mots (JSON) trouvé dans la réponse de Claude';
  }
}

bool get _both => store.active.length > 1;
bool get _hok => store.active.contains('hok');

/// The language(s) Claude should use, as a French phrase.
String get _target => _both
    ? 'en mandarin de Taïwan (華語) et en taïwanais (台語), comme on les mélange à Taipei'
    : _hok
    ? 'en taïwanais (台語, pas en mandarin)'
    : 'en mandarin de Taïwan (華語)';

String get _romanization => _both
    ? 'le pinyin pour le mandarin et le Tâi-lô pour le taïwanais'
    : _hok
    ? 'le Tâi-lô'
    : 'le pinyin';

String get _deckFormat =>
    'Termine par un bloc de code JSON contenant un tableau des nouveaux mots, au format exact : '
    '[{"lang": "hok" ou "man", "hanzi": "…", "roman": "…", "fr": "…", "tag": "…"}] '
    '(lang : hok = taïwanais, man = mandarin${_both ? " ; donne chaque mot dans les deux langues" : ""} ; '
    'caractères traditionnels — pour le taïwanais ceux recommandés par le ministère de l’Éducation ; '
    'roman = Tâi-lô avec tons pour hok, pinyin avec tons pour man ; tag = thème court en français), '
    "pour que je puisse l'importer dans mon application.";

const _scenarios = {
  'Marché de nuit': 'au marché de nuit (je commande à manger)',
  'Marché': 'au marché traditionnel (菜市仔, je marchande des fruits)',
  'Famille': 'chez les grands-parents d’un ami (阿公 et 阿媽 ne parlent que taïwanais)',
  'Temple': 'au temple (on parle des coutumes et des offrandes)',
  'Rencontre': 'avec un(e) nouvel(le) ami(e) taïwanais(e) (on se présente)',
};

String _profile() {
  final seen = store.words.where((w) => !w.isNew).toList();
  final hard = (seen.where((w) => w.lapses > 0 || w.ease < 2.3).toList()..sort((a, b) => b.lapses.compareTo(a.lapses)))
      .take(12);
  final recent = store.mistakes.map(store.byKey).whereType<Word>().take(10);
  String fmt(Word w) => '${w.hanzi} (${langs[w.lang]} ${w.roman}, « ${w.meaning} »)';
  final tags = {for (final w in seen) w.tag};
  return '''Mon profil d'apprenant :
- Francophone, je vis à Taipei / je m'y prépare. J'apprends ${[if (_hok) "le taïwanais (台語 Tâi-gí, hokkien de Taïwan ; caractères recommandés par le ministère de l'Éducation, Tâi-lô avec tons, signale les sandhis tonals quand c'est utile)", if (store.active.contains('man')) "le mandarin de Taïwan (華語, caractères traditionnels, pinyin et zhuyin, vocabulaire et prononciation taïwanais)"].join(' et ')}.${_both ? " Ne confonds jamais les deux langues : indique toujours laquelle tu utilises." : ""} Réponds-moi en français.
- Mots étudiés : ${seen.length}/${store.words.length}, dont ${seen.where((w) => w.mastered).length} maîtrisés. Série : ${store.streak} jour(s).
- Thèmes / niveaux vus : ${tags.isEmpty ? 'aucun' : tags.join(', ')}. Niveau en cours : ${store.words.where((w) => w.isNew).firstOrNull?.tag ?? 'tout vu'}.
- Mots difficiles : ${hard.isEmpty ? "aucun pour l'instant" : hard.map(fmt).join(', ')}.
- Erreurs récentes : ${recent.isEmpty ? 'aucune' : recent.map(fmt).join(', ')}.''';
}

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final sentence = TextEditingController();
  final deck = TextEditingController();

  @override
  void dispose() {
    sentence.dispose();
    deck.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  Future<void> send(String task) async {
    final prompt = '${_profile()}\n\n$task';
    if (await claude.invokeMethod<bool>('openClaude', prompt) ?? false) return;
    // Claude app not installed (or refused the intent): generic share sheet.
    await Clipboard.setData(ClipboardData(text: prompt));
    _snack('App Claude introuvable — message copié');
    await SharePlus.instance.share(ShareParams(text: prompt));
  }

  void import() {
    _snack(importDeck(deck.text));
    deck.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('Votre prof Claude', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'Choisissez une activité : Claude s’ouvre avec un message prêt, contenant votre profil (mots difficiles, '
          'erreurs récentes). Pour récupérer les nouveaux mots, partagez la réponse de Claude vers LLLearner.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _Action(
          icon: Icons.auto_stories,
          title: 'Leçon sur mesure',
          subtitle: 'Vos mots difficiles en contexte + 8 nouveaux mots à importer',
          onTap: () => send(
            'Crée-moi une leçon de 15 minutes adaptée à ce profil : réutilise mes mots difficiles dans des phrases, '
            'introduis 8 nouveaux mots utiles au quotidien $_target, puis un court dialogue avec $_romanization et traduction. '
            'Ajoute 3 petits exercices (j’y répondrai ensuite). $_deckFormat',
          ),
        ),
        _Action(
          icon: Icons.psychology,
          title: 'Expliquer mes erreurs',
          subtitle: 'Mnémotechniques, pièges de tons, exemples',
          onTap: () => send(
            'Explique-moi mes erreurs récentes et mes mots difficiles : pour chacun, un moyen mnémotechnique '
            '(décomposition des caractères), le piège de prononciation ou de ton, et 2 phrases d’exemple. '
            'Termine par un mini-quiz de 5 questions et attends mes réponses.',
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.forum, color: cs.primary),
                    const SizedBox(width: 12),
                    Text('Conversation', style: tt.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Jeu de rôle avec corrections à chaque réplique', style: tt.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: label, value: where) in _scenarios.entries)
                      ActionChip(
                        label: Text(label),
                        onPressed: () => send(
                          'Jouons une conversation $where à Taipei. Tu joues le/la Taïwanais(e), moi l’apprenant. '
                          'Règles : une seule réplique à la fois, $_target, simple et adaptée à mon niveau (réutilise mes mots), '
                          'avec $_romanization et la traduction française entre parenthèses. Après chacune de mes réponses, '
                          'corrige brièvement mes erreurs (tons, grammaire, tournure plus naturelle) avant de continuer. '
                          'Commence !',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.spellcheck, color: cs.primary),
                    const SizedBox(width: 12),
                    Text('Corriger ma phrase', style: tt.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sentence,
                  style: zh(18),
                  decoration: const InputDecoration(hintText: '我欲啉茶… / Guá beh lim tê…', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    if (sentence.text.trim().isEmpty) return;
                    send(
                      'Corrige cette phrase que j’ai écrite (caractères et/ou romanisation) : « ${sentence.text.trim()} ». '
                      'Dis d’abord si c’est du mandarin, du taïwanais ou un mélange. Explique les erreurs en français '
                      '(tons, grammaire, mot de l’autre langue à remplacer), donne la version la plus naturelle '
                      '(caractères + romanisation) et une variante.',
                    );
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer à Claude'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: cs.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download, color: cs.onSecondaryContainer),
                    const SizedBox(width: 12),
                    Text('Importer les mots de Claude', style: tt.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Plus simple : dans Claude, partagez la réponse vers LLLearner. Sinon, collez-la ici.',
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deck,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: '[{"lang": "hok", "hanzi": "菜市仔", "roman": "tshài-tshī-á", "fr": "marché", …}]',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: cs.surface,
                    suffixIcon: IconButton(
                      tooltip: 'Coller',
                      icon: const Icon(Icons.content_paste),
                      onPressed: () async => deck.text = (await Clipboard.getData('text/plain'))?.text ?? '',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: import, icon: const Icon(Icons.add), label: const Text('Importer')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.open_in_new),
        ),
      ),
    );
  }
}
