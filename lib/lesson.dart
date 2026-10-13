import 'dart:math';

import 'package:flutter/material.dart';

import 'characters.dart';
import 'course.dart';
import 'exercise.dart';
import 'fiche.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

sealed class _Step {}

class _TipStep extends _Step {
  _TipStep(this.tip);
  final Tip tip;
}

class _IntroStep extends _Step {
  _IntroStep(this.word);
  final Word word;
}

class _ExStep extends _Step {
  _ExStep(this.exercise);
  final Exercise exercise;
}

/// A lesson: each new word is introduced (characters, pronunciation, audio, an example),
/// then practised in small batches, then all together. Missed questions come back at
/// the end. Words enter the review schedule only when the lesson is finished.
/// A lesson already learned is practised without the introductions.
class LessonPage extends StatefulWidget {
  const LessonPage(this.lesson, {super.key});
  final Lesson lesson;

  static Future<void> open(BuildContext context, Lesson lesson) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => LessonPage(lesson)));

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  final rng = Random();
  late final List<Word> toLearn = widget.lesson.words.where((w) => w.isNew).toList();
  late final bool practice = toLearn.isEmpty;
  late final List<Word> pool = distractorPool(widget.lesson.words, also: widget.lesson.words);
  late final Set<Word> familiar = widget.lesson.words.toSet();
  final steps = <_Step>[];
  final known = <Word>{}, stumbled = <Word>{};
  final retries = <Word, int>{};
  int i = 0, right = 0, answered = 0;
  bool finished = false, quitting = false;

  @override
  void initState() {
    super.initState();
    final words = practice ? widget.lesson.words : toLearn;
    if (!practice && store.learned.isEmpty) steps.addAll(store.course.tips.map(_TipStep.new));
    if (practice) {
      steps.addAll(
        _exercises([
          for (final w in words) ...[Kind.meaning, Kind.recall, _ear()].map((k) => (w, k)),
        ]),
      );
    } else {
      // Three words at a time: introduce, then recognize; then everything in recall.
      for (var c = 0; c < words.length; c += 3) {
        final chunk = words.sublist(c, min(c + 3, words.length));
        steps.addAll(chunk.map(_IntroStep.new));
        steps.addAll(_exercises([for (final w in chunk) (w, Kind.meaning)]));
      }
      steps.addAll(
        _exercises([
          for (final w in words) ...[(w, Kind.recall), (w, _ear())],
        ]),
      );
    }
  }

  Kind _ear() => rng.nextBool() ? Kind.listen : Kind.tones;

  /// Shuffled exercises; a kind the word can't have (no tone, too few distractors)
  /// falls back to a meaning question, and is dropped if even that is impossible.
  List<_Step> _exercises(List<(Word, Kind)> list) => [
    for (final (w, k) in list..shuffle(rng))
      if (makeExercise(w, k, pool, rng, familiar: familiar) ??
              makeExercise(w, Kind.meaning, pool, rng, familiar: familiar)
          case final ex?)
        _ExStep(ex),
  ];

  void next() {
    tts.stop();
    if (i + 1 >= steps.length) return finish();
    setState(() => i++);
  }

  void answered_(Exercise ex, bool ok) {
    answered++;
    if (ok) right++;
    if (practice || !ok) store.quizAnswer(ex.word, ok); // misses feed "Points faibles"
    if (!ok) {
      stumbled.add(ex.word);
      final n = retries[ex.word] ?? 0;
      if (n < 2) {
        retries[ex.word] = n + 1;
        final again = makeExercise(ex.word, ex.kind, pool, rng, familiar: familiar);
        if (again != null) steps.add(_ExStep(again));
      }
    }
  }

  void knowIt(Word w) {
    store.markKnown(w);
    known.add(w);
    setState(() {
      steps.removeWhere(
        (s) =>
            steps.indexOf(s) > i &&
            switch (s) {
              _IntroStep(:final word) || _ExStep(exercise: Exercise(:final word)) => word == w,
              _ => false,
            },
      );
    });
    next();
  }

  void finish() {
    for (final w in toLearn) {
      if (!known.contains(w)) store.learn(w, stumbled: stumbled.contains(w));
    }
    setState(() => finished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (finished) return _Done(this);
    final step = steps[i];
    return PopScope(
      canPop: i == 0 || quitting,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        if (await confirmQuit(context, 'Les mots de cette leçon ne seront pas enregistrés.') && context.mounted) {
          setState(() => quitting = true); // lets the pop through once rebuilt
          WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? Navigator.pop(context) : null);
        }
      },
      child: Scaffold(
        appBar: SessionBar(progress: i / steps.length),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(i),
            child: switch (step) {
              _TipStep(:final tip) => _TipView(tip, onNext: next),
              _IntroStep(:final word) => _IntroView(word, onNext: next, onKnown: () => knowIt(word)),
              _ExStep(:final exercise) => ExerciseView(
                exercise: exercise,
                onAnswer: (ok) => answered_(exercise, ok),
                onDone: (_) => next(),
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Bottom action of the lesson's reading steps.
class _BottomButton extends StatelessWidget {
  const _BottomButton(this.label, this.onPressed, {this.secondary});
  final String label;
  final VoidCallback onPressed;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(label),
          ),
          ?secondary,
        ],
      ),
    ),
  );
}

class _TipView extends StatelessWidget {
  const _TipView(this.tip, {required this.onNext});
  final Tip tip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = context.palette;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Text('Avant de commencer', style: tt.labelLarge?.copyWith(color: cs.tertiary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(tip.title, style: tt.headlineMedium),
              const SizedBox(height: 12),
              Text(tip.body, style: tt.bodyLarge),
              const SizedBox(height: 20),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (n, e) in tip.examples.indexed)
                      ListTile(
                        onTap: () => speak(e.hanzi),
                        leading: CircleAvatar(
                          backgroundColor: palette.tones[min(n, 4)].withValues(alpha: 0.15),
                          child: Text(e.hanzi, style: script(20, color: palette.tones[min(n, 4)])),
                        ),
                        title: Row(
                          children: [
                            Roman(e.roman, style: tt.titleLarge),
                            const SizedBox(width: 8),
                            Text(e.fr, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                        subtitle: Text(e.note),
                        trailing: Icon(Icons.volume_up_outlined, color: cs.primary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BottomButton('J’ai compris', onNext),
      ],
    );
  }
}

class _IntroView extends StatefulWidget {
  const _IntroView(this.word, {required this.onNext, required this.onKnown});
  final Word word;
  final VoidCallback onNext, onKnown;

  @override
  State<_IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<_IntroView> {
  @override
  void initState() {
    super.initState();
    play(widget.word);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final w = widget.word;
    final example = store.examples(w).firstOrNull;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  Icon(Icons.fiber_new_outlined, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Text('Nouveau mot', style: tt.labelLarge?.copyWith(color: cs.tertiary)),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                  child: Column(
                    children: [
                      FittedBox(child: Hanzi(w.hanzi, w.roman, size: 80, weight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Pronunciation(w, size: 26),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => play(w),
                            icon: const Icon(Icons.volume_up_rounded),
                            label: const Text('Écouter'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => play(w, slow: true),
                            icon: const Icon(Icons.slow_motion_video),
                            label: const Text('Lentement'),
                          ),
                        ],
                      ),
                      const Divider(height: 36),
                      Text(w.fr, textAlign: TextAlign.center, style: tt.headlineSmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Les caractères', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              CharacterBreakdown(w),
              if (example != null) ...[
                const SizedBox(height: 20),
                Text('En contexte', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                ExampleTile(example, highlight: w.hanzi),
              ],
            ],
          ),
        ),
        _BottomButton(
          'Continuer',
          widget.onNext,
          secondary: TextButton(onPressed: widget.onKnown, child: const Text('Je connais déjà ce mot')),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done(this.s);
  final _LessonPageState s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final next = store.nextLesson;
    final learned = s.toLearn.where((w) => !s.known.contains(w)).toList();
    final pct = s.answered == 0 ? 100 : (100 * s.right / s.answered).round();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                      child: Icon(Icons.celebration, size: 48, color: cs.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s.practice ? 'Entraînement terminé !' : 'Leçon terminée !',
                    textAlign: TextAlign.center,
                    style: tt.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.practice
                        ? '$pct % de bonnes réponses'
                        : '${learned.length} mot${learned.length > 1 ? 's' : ''} appris · $pct % de bonnes réponses\n'
                              'Ils reviendront dans vos révisions au bon moment.',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in s.practice ? s.widget.lesson.words : learned)
                        ActionChip(
                          onPressed: () => play(w),
                          avatar: s.stumbled.contains(w) ? Icon(Icons.replay, color: cs.tertiary) : null,
                          label: Text('${w.hanzi}  ${w.fr.split(' ;').first}', style: script(15)),
                        ),
                    ],
                  ),
                  if (s.stumbled.isNotEmpty && !s.practice) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Les mots marqués ↻ reviendront un peu plus tôt.',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  if (next != null && !s.practice)
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () =>
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LessonFiche(next))),
                      child: const Text('Leçon suivante'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Terminer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
