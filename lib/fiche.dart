import 'package:flutter/material.dart';

import 'characters.dart';
import 'coach.dart';
import 'lesson.dart';
import 'store.dart';
import 'widgets.dart';

/// The lesson's fiche, to read before being quizzed: every word with its pronunciation, meaning
/// and example sentences (whose words open on tap), and the assistant for a full explanation.
class LessonFiche extends StatelessWidget {
  const LessonFiche(this.lesson, {super.key});
  final Lesson lesson;

  static Future<void> open(BuildContext context, Lesson lesson) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => LessonFiche(lesson)));

  String get _explain {
    final c = store.course;
    final words = lesson.words.map((w) => '${w.hanzi} (${w.roman}, « ${w.fr} »)').join(', ');
    return 'Je vais apprendre cette leçon : $words. Fais-m’en une fiche complète à lire avant le quiz : pour '
        'chaque mot, son sens et ses usages, ${c.hasCharacters ? 'la décomposition de ses caractères, ' : ''}'
        'les pièges de ${c.hasTones ? 'ton ou de ' : ''}prononciation et 2 phrases d’exemple (${c.writing}, '
        '${c.romanization}, français) ; puis les points de '
        'grammaire utiles, un court dialogue qui emploie tous ces mots, et 3 questions de compréhension '
        'auxquelles je répondrai.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('${lesson.unit.name} · leçon ${lesson.number}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Fiche de leçon : lisez et écoutez chaque mot avant le quiz. Touchez '
              '${store.course.hasCharacters ? 'un caractère pour voir comment il est formé, et ' : ''}'
              'un mot des exemples pour le décortiquer.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          for (final w in lesson.words)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Hanzi(w.hanzi, w.roman, size: 40, weight: FontWeight.w600),
                              Pronunciation(w, size: 18, align: TextAlign.start),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Écouter',
                          onPressed: () => play(w),
                          icon: const Icon(Icons.volume_up_rounded),
                        ),
                        IconButton(
                          tooltip: 'Écouter lentement',
                          onPressed: () => play(w, slow: true),
                          icon: const Icon(Icons.slow_motion_video),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(w.fr, style: tt.titleMedium),
                    const SizedBox(height: 8),
                    CharacterBreakdown(w),
                    for (final e in store.examples(w)) ExampleTile(e, highlight: w.hanzi),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => askAssistant(_explain),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Explication complète par l’assistant IA'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LessonPage(lesson))),
            child: Text(lesson.done ? 'S’entraîner' : 'Commencer la leçon'),
          ),
        ),
      ),
    );
  }
}
