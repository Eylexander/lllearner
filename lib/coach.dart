import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';

// The Claude bridge: no API (the user wants their subscription, which third-party
// apps can't use). `openClaude` (MainActivity.kt) opens the Claude app directly
// with a prefilled prompt carrying the learner profile; Claude's replies come back
// through the Android share menu ("sharedText") or by pasting, then `importDeck`.
const claude = MethodChannel('lllearner/claude');

/// Imports the vocabulary JSON from an AI assistant reply; returns a user-facing message.
String importDeck(String text) {
  try {
    final list = Store.parseDeck(text, lang: store.course.id);
    final n = store.addWords(list);
    return list.isEmpty
        ? 'Aucun mot valide trouvé'
        : '$n mot(s) ajouté(s) au début du parcours${list.length > n ? ', ${list.length - n} déjà connu(s)' : ''}';
  } catch (_) {
    return 'Aucun bloc de mots (JSON) trouvé dans la réponse de l’assistant IA';
  }
}

String get _deckFormat =>
    'Termine par un bloc de code JSON contenant un tableau des nouveaux mots, au format exact : '
    '[{"lang": "${store.course.id}", "hanzi": "…", "roman": "…", "fr": "…", "tag": "…"}] '
    '(hanzi = l’écriture du mot, roman = ${store.course.romanization} avec tons, tag = thème court en français), '
    "pour que je puisse l'importer dans mon application.";

String _profile() {
  final c = store.course;
  final seen = store.learned.toList();
  final hard = (seen.where((w) => w.weak).toList()..sort((a, b) => b.lapses.compareTo(a.lapses))).take(12);
  final recent = store.mistakes.map(store.byKey).whereType<Word>().take(10);
  String fmt(Word w) => '${w.hanzi} (${w.roman}, « ${w.fr} »)';
  final next = store.nextLesson;
  return '''Mon profil d'apprenant :
- Francophone, j'apprends ${c.claude}. Réponds-moi en français.
- Mots appris : ${seen.length}/${store.words.length}, dont ${seen.where((w) => w.mastered).length} maîtrisés. Série : ${store.streak} jour(s).
- Où j'en suis dans le cours : ${next == null ? 'tout vu' : '${next.unit.section}, ${next.unit.name}'}.
- Derniers mots appris : ${seen.reversed.take(12).map((w) => w.hanzi).join('、')}.
- Mots difficiles : ${hard.isEmpty ? "aucun pour l'instant" : hard.map(fmt).join(', ')}.
- Erreurs récentes : ${recent.isEmpty ? 'aucune' : recent.map(fmt).join(', ')}.''';
}

/// Opens the assistant with [task] after the learner profile.
Future<void> askAssistant(String task) async {
  final prompt = '${_profile()}\n\n$task';
  if (await claude.invokeMethod<bool>('openClaude', prompt).catchError((_) => false) ?? false) return;
  // Assistant app not installed (or refused the intent): generic share sheet.
  await Clipboard.setData(ClipboardData(text: prompt));
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Assistant IA introuvable — message copié')));
  await SharePlus.instance.share(ShareParams(text: prompt));
}

/// The "Assistant" tab.
class CoachTab extends StatefulWidget {
  const CoachTab({super.key});

  @override
  State<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends State<CoachTab> {
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
    ..showSnackBar(SnackBar(content: Text(msg)));

  void import() {
    _snack(importDeck(deck.text));
    deck.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = store.course;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Choisissez une activité : l’assistant IA s’ouvre avec un message prêt, qui contient votre profil (mots '
            'difficiles, erreurs récentes). Pour récupérer de nouveaux mots, partagez ensuite la réponse de l’assistant '
            'vers LLLearner.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        _Action(
          icon: Icons.auto_stories,
          title: 'Leçon sur mesure',
          subtitle: 'Vos mots difficiles en contexte, et 8 nouveaux mots à importer',
          onTap: () => askAssistant(
            'Crée-moi une leçon de 15 minutes adaptée à ce profil : réutilise mes mots difficiles dans des phrases, '
            'introduis 8 nouveaux mots utiles au quotidien, puis un court dialogue avec ${c.romanization} et '
            'traduction. Ajoute 3 petits exercices (j’y répondrai ensuite). $_deckFormat',
          ),
        ),
        _Action(
          icon: Icons.psychology,
          title: 'Expliquer mes erreurs',
          subtitle: 'Moyens mnémotechniques, pièges de tons, exemples',
          onTap: () => askAssistant(
            'Explique-moi mes erreurs récentes et mes mots difficiles : pour chacun, un moyen mnémotechnique '
            '(décomposition des caractères), le piège de prononciation ou de ton, et 2 phrases d’exemple. '
            'Termine par un mini-quiz de 5 questions et attends mes réponses.',
          ),
        ),
        _Action(
          icon: Icons.menu_book,
          title: 'Petite histoire',
          subtitle: 'Un court texte avec uniquement les mots que je connais',
          onTap: () => askAssistant(
            'Écris une très courte histoire (6 à 8 phrases) en utilisant presque uniquement mes derniers mots '
            'appris et des mots plus simples. Donne chaque phrase en caractères, puis en ${c.romanization}, puis '
            'en français, et pose-moi 3 questions de compréhension à la fin.',
          ),
        ),
        const SizedBox(height: 4),
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
                    for (final MapEntry(key: label, value: where) in c.scenarios.entries)
                      ActionChip(
                        label: Text(label),
                        onPressed: () => askAssistant(
                          'Jouons une conversation $where. Tu joues mon interlocuteur, moi l’apprenant. Règles : une '
                          'seule réplique à la fois, simple et adaptée à mon niveau (réutilise mes mots), avec '
                          '${c.romanization} et la traduction française entre parenthèses. Après chacune de mes '
                          'réponses, corrige brièvement mes erreurs (tons, grammaire, tournure plus naturelle) avant '
                          'de continuer. Commence !',
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
                  style: script(18),
                  decoration: InputDecoration(hintText: c.sentenceHint, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    if (sentence.text.trim().isEmpty) return;
                    askAssistant(
                      'Corrige cette phrase que j’ai écrite (caractères et/ou ${c.romanization}) : '
                      '« ${sentence.text.trim()} ». Explique les erreurs en français (tons, grammaire, mot plus '
                      'naturel à Taïwan), donne la version la plus naturelle (caractères + ${c.romanization}) et '
                      'une variante.',
                    );
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer à l’assistant IA'),
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
                    Text(
                      'Importer les mots de l’assistant IA',
                      style: tt.titleMedium?.copyWith(color: cs.onSecondaryContainer),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Le plus simple : dans l’assistant IA, partagez la réponse vers LLLearner. Sinon, collez-la ici. Les mots '
                  'importés deviennent vos prochaines leçons.',
                  style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deck,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: '[{"hanzi": "市場", "roman": "shìchǎng", "fr": "marché", …}]',
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
