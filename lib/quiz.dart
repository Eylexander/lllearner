import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';

enum _Kind { meaning, write, listen }

class _Q {
  _Q(this.word, this.options, this.kind);
  final Word word;
  final List<Word> options;
  final _Kind kind;
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.go});
  final ValueChanged<int> go;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final rng = Random();
  late List<_Q> qs;
  int i = 0, score = 0;
  Word? picked;

  @override
  void initState() {
    super.initState();
    restart();
  }

  void restart() {
    // Quiz on studied words when there are enough, otherwise on everything; only words
    // with a French meaning (dictionary-only words have a Mandarin definition instead).
    final quizzable = store.words.where((w) => w.fr.isNotEmpty);
    final seen = quizzable.where((w) => !w.isNew).toList();
    final pool = seen.length >= 4 ? seen : [...quizzable];
    final targets = (pool..shuffle(rng)).take(10);
    qs = [
      for (final w in targets)
        () {
          // Same-theme distractors first; never two options that sound or translate alike.
          final others = quizzable.where((o) => o.lang == w.lang && o.roman != w.roman && o.fr != w.fr).toList()
            ..shuffle(rng);
          final opts = [
            w,
            ...[...others.where((o) => o.tag == w.tag), ...others.where((o) => o.tag != w.tag)].take(3),
          ]..shuffle(rng);
          // Listening only for words that have a recording.
          return _Q(w, opts, _Kind.values[rng.nextInt(w.hasAudio ? _Kind.values.length : 2)]);
        }(),
    ];
    i = score = 0;
    picked = null;
    prefetch(qs.map((q) => q.word));
    _autoplay();
  }

  void _autoplay() {
    if (i < qs.length && qs[i].kind == _Kind.listen) play(qs[i].word);
  }

  void answer(Word o) {
    if (picked != null) return;
    final q = qs[i];
    final ok = o == q.word;
    ok ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      picked = o;
      if (ok) score++;
    });
    if (q.kind != _Kind.listen) play(q.word);
    store.quizAnswer(q.word, ok);
  }

  void next() {
    setState(() {
      i++;
      picked = null;
    });
    _autoplay();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (i >= qs.length) {
      final pct = score / qs.length;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pct >= .8
                    ? '🏆'
                    : pct >= .5
                    ? '💪'
                    : '📚',
                style: tt.displayLarge,
              ),
              const SizedBox(height: 16),
              Text('$score / ${qs.length}', style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                pct >= .8
                    ? '誠讚！Excellent !'
                    : pct >= .5
                    ? 'Pas mal, continuez !'
                    : 'On révise et on recommence !',
                style: tt.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => setState(restart),
                icon: const Icon(Icons.replay),
                label: const Text('Rejouer'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => widget.go(4),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyser mes erreurs avec Claude'),
              ),
            ],
          ),
        ),
      );
    }

    final q = qs[i];
    final prompt = switch (q.kind) {
      _Kind.meaning => Column(
        children: [
          Text('Que signifie (${langs[q.word.lang]})…', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(q.word.hanzi, style: zh(64, weight: FontWeight.w600)),
          ),
        ],
      ),
      _Kind.write => Column(
        children: [
          Text(
            'Comment dit-on en ${langNames[q.word.lang]!.toLowerCase()}…',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text('« ${q.word.fr} »', textAlign: TextAlign.center, style: tt.headlineSmall),
        ],
      ),
      _Kind.listen => Column(
        children: [
          Text(
            'Écoutez (${langs[q.word.lang]}) et choisissez',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          IconButton.filled(
            iconSize: 48,
            padding: const EdgeInsets.all(20),
            onPressed: () => play(q.word),
            icon: const Icon(Icons.volume_up_rounded),
          ),
        ],
      ),
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: i / qs.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${i + 1}/${qs.length}', style: tt.labelLarge),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20), child: prompt),
              ),
              const SizedBox(height: 20),
              for (final o in q.options) ...[
                _Option(
                  word: o,
                  showFr: q.kind == _Kind.meaning,
                  state: picked == null
                      ? null
                      : o == q.word
                      ? true
                      : o == picked
                      ? false
                      : null,
                  revealed: picked != null,
                  onTap: () => answer(o),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: AnimatedOpacity(
            opacity: picked == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: FilledButton(
              onPressed: picked == null ? null : next,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(i + 1 == qs.length ? 'Voir le score' : 'Suivant'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.word,
    required this.showFr,
    required this.state,
    required this.revealed,
    required this.onTap,
  });
  final Word word;
  final bool showFr, revealed;
  final bool? state; // true = correct answer, false = wrong pick
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = state == null
        ? null
        : state!
        ? Colors.green
        : cs.error;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.15) ?? cs.surfaceContainerLow,
        border: Border.all(color: color ?? cs.outlineVariant, width: color == null ? 1 : 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      showFr
                          ? Text(word.fr, style: tt.titleMedium)
                          : Text(word.hanzi, style: zh(26, weight: FontWeight.w500)),
                      if (revealed)
                        Text(
                          showFr ? '${word.hanzi} · ${word.roman}' : '${word.roman} · ${word.fr}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (color != null) Icon(state! ? Icons.check_circle : Icons.cancel, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
