import 'dart:math';

import 'package:flutter/material.dart';

import 'exercise.dart';
import 'lesson.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

enum Mode {
  mixed('Quiz mixte', '10 questions variées sur vos mots', Icons.quiz_outlined, [
    Kind.meaning,
    Kind.recall,
    Kind.listen,
    Kind.tones,
  ]),
  listen('Écoute', 'Reconnaître les mots à l’oreille', Icons.hearing, [Kind.listen]),
  tones('Tons', 'Retrouver les bons tons d’un mot', Icons.graphic_eq, [Kind.tones]),
  weak('Points faibles', 'Vos erreurs récentes et mots difficiles', Icons.healing_outlined, [
    Kind.meaning,
    Kind.recall,
    Kind.listen,
  ]);

  const Mode(this.title, this.subtitle, this.icon, this.kinds);
  final String title, subtitle;
  final IconData icon;
  final List<Kind> kinds;
}

/// Words a quiz may ask about: only learned ones, never the rest of the deck.
List<Word> _targets(Mode mode) => mode == Mode.weak
    ? {
        ...store.mistakes.map(store.byKey).whereType<Word>().where((w) => !w.isNew),
        ...store.learned.where((w) => w.weak),
      }.toList()
    : store.learned.toList();

const _minLearned = 4;

/// The "Pratiquer" tab.
class PracticeTab extends StatelessWidget {
  const PracticeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final learned = store.learned.length;
    if (learned < _minLearned) {
      final next = store.nextLesson;
      return EmptyState(
        icon: Icons.quiz_outlined,
        title: 'Apprenez d’abord quelques mots',
        message:
            'Les quiz portent uniquement sur les mots vus en leçon. '
            'Encore ${_minLearned - learned} mot${_minLearned - learned > 1 ? 's' : ''} et c’est parti !',
        actions: [
          if (next != null)
            FilledButton.icon(
              onPressed: () => LessonPage.open(context, next),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Continuer le cours'),
            ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            'Entraînez-vous sur les $learned mots que vous avez appris.',
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        for (final mode in Mode.values) ...[
          () {
            final n = _targets(mode).length;
            final ok = mode == Mode.weak ? n > 0 : true;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                enabled: ok,
                onTap: () => QuizSession.open(context, mode),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                leading: CircleAvatar(
                  backgroundColor: ok ? cs.secondaryContainer : cs.surfaceContainerHighest,
                  child: Icon(mode.icon, color: ok ? cs.onSecondaryContainer : cs.outline),
                ),
                title: Text(mode.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(ok ? mode.subtitle : 'Aucun mot difficile pour l’instant, bravo !'),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          }(),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class QuizSession extends StatefulWidget {
  const QuizSession(this.mode, {super.key});
  final Mode mode;

  static Future<void> open(BuildContext context, Mode mode) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => QuizSession(mode)));

  @override
  State<QuizSession> createState() => _QuizSessionState();
}

class _QuizSessionState extends State<QuizSession> {
  final rng = Random();
  late List<Exercise> qs;
  final missed = <Word>[];
  int i = 0, score = 0;

  @override
  void initState() {
    super.initState();
    restart();
  }

  /// Ten questions; weak words (lapses, recent mistakes, short intervals) come up more.
  void restart() {
    final targets = _targets(widget.mode);
    final pool = distractorPool(targets);
    double weight(Word w) =>
        1 + 2 * w.lapses + (store.mistakes.contains(w.key) ? 3 : 0) + (w.interval < 3 ? 1 : 0) + (w.ease < 2.3 ? 1 : 0);
    final picked = <Word>[];
    final left = [...targets];
    while (picked.length < 10 && left.isNotEmpty) {
      var r = rng.nextDouble() * left.fold(0.0, (s, w) => s + weight(w));
      final w = left.firstWhere((w) => (r -= weight(w)) <= 0, orElse: () => left.last);
      picked.add(w);
      left.remove(w);
    }
    qs = [for (final w in picked) ?_exercise(w, pool)];
    i = score = 0;
    missed.clear();
  }

  /// A question of one of the mode's kinds the word allows, else a meaning question.
  Exercise? _exercise(Word w, List<Word> pool) {
    for (final k in widget.mode.kinds.toList()..shuffle(rng)) {
      if (makeExercise(w, k, pool, rng) case final ex?) return ex;
    }
    return makeExercise(w, Kind.meaning, pool, rng);
  }

  @override
  Widget build(BuildContext context) {
    if (i >= qs.length) return _results(context);
    final q = qs[i];
    return Scaffold(
      appBar: SessionBar(
        progress: i / qs.length,
        trailing: Center(child: Text('${i + 1}/${qs.length}', style: Theme.of(context).textTheme.labelLarge)),
      ),
      body: KeyedSubtree(
        key: ValueKey(i),
        child: ExerciseView(
          exercise: q,
          onAnswer: (ok) {
            if (ok) {
              score++;
            } else {
              missed.add(q.word);
            }
            store.quizAnswer(q.word, ok);
          },
          onDone: (_) => setState(() => i++),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pct = qs.isEmpty ? 0 : score / qs.length;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Center(
            child: ProgressRing(
              value: pct.toDouble(),
              size: 120,
              stroke: 10,
              child: Text('$score/${qs.length}', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            pct >= .8
                ? 'Excellent ! 太棒了！'
                : pct >= .5
                ? 'Pas mal, continuez !'
                : 'On révise et on recommence !',
            textAlign: TextAlign.center,
            style: tt.headlineSmall,
          ),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('À revoir', style: tt.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final w in missed)
                    ListTile(
                      onTap: () => play(w),
                      leading: Text(w.hanzi, style: script(24, weight: FontWeight.w600)),
                      title: Text(w.fr, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(pronLine(w), style: script(13, color: cs.onSurfaceVariant)),
                      trailing: Icon(Icons.volume_up_outlined, color: palette.warning.color),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => setState(restart),
            icon: const Icon(Icons.replay),
            label: const Text('Rejouer'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Terminer'),
          ),
        ],
      ),
    );
  }
}
