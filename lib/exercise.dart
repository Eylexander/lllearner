import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pinyin.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

/// meaning: characters → French; recall: French → characters; listen: audio → French;
/// tones: characters and audio → the pinyin with the right tones.
enum Kind { meaning, recall, listen, tones }

class Option {
  const Option(this.text, {this.word, this.correct = false});
  final String text;
  final Word? word; // the word this option stands for (revealed after answering)
  final bool correct;
}

class Exercise {
  Exercise(this.word, this.kind, this.options);
  final Word word;
  final Kind kind;
  final List<Option> options;
}

/// The first sense without notes: 'Bonjour (le matin) ; salut' → 'bonjour'.
String _core(String fr) => plain(fr.split(';').first.replaceAll(RegExp(r'\(.*?\)'), '').trim());

/// Words to draw wrong answers from: the given ones, words already learned, and the
/// words next to [targets] in the course (same level) — never the whole deck, so a
/// beginner isn't shown advanced vocabulary.
List<Word> distractorPool(Iterable<Word> targets, {Iterable<Word> also = const []}) {
  final words = store.words;
  final index = {for (final (i, w) in words.indexed) w.key: i};
  return {
    ...also,
    ...store.learned,
    for (final t in targets)
      if (index[t.key] case final i?) ...words.sublist(max(0, i - 30), min(words.length, i + 30)),
  }.toList();
}

/// An exercise of [kind] on [w] with three wrong options from [pool], or null when the
/// pool can't provide three clearly different ones (or the word has no tone to ask).
Exercise? makeExercise(Word w, Kind kind, List<Word> pool, Random rng, {Set<Word> familiar = const {}}) {
  if (kind == Kind.tones) {
    if (!store.course.hasTones) return null;
    final wrong = toneVariants(w.roman, 3, rng);
    if (wrong.length < 3) return null;
    return Exercise(w, kind, [Option(w.roman, word: w, correct: true), for (final r in wrong) Option(r)]..shuffle(rng));
  }
  final core = _core(w.fr), sound = plain(w.roman);
  final others =
      pool
          .where(
            (o) =>
                o.lang == w.lang &&
                o.hanzi != w.hanzi &&
                plain(o.roman) != sound &&
                _core(o.fr) != core &&
                !o.fr.contains(w.fr) &&
                !w.fr.contains(o.fr),
          )
          .toList()
        ..shuffle(rng);
  // Look-alikes, so no option can be ruled out without knowing the word: words already seen
  // (learned, or in [familiar], e.g. the lesson's) rather than strangers, as many characters
  // as the answer, sharing one of its characters, same theme.
  int rank(Word o) =>
      (!o.isNew || familiar.contains(o) ? 0 : 6) +
      (o.hanzi.length == w.hanzi.length ? 0 : 3) +
      (o.tag == w.tag ? 0 : 1) -
      (o.hanzi.split('').any(w.hanzi.contains) ? 1 : 0);
  others.sort((a, b) => rank(a).compareTo(rank(b)));
  final picked = <Word>[];
  for (final o in others) {
    if (picked.length == 3) break;
    if (picked.any((p) => p.hanzi == o.hanzi || _core(p.fr) == _core(o.fr))) continue;
    picked.add(o);
  }
  if (picked.length < 3) return null;
  String label(Word o) => kind == Kind.recall ? o.hanzi : o.fr;
  return Exercise(
    w,
    kind,
    [Option(label(w), word: w, correct: true), for (final o in picked) Option(label(o), word: o)]..shuffle(rng),
  );
}

/// One multiple-choice question; after an answer, a feedback panel with the right
/// word and a Continue button that calls [onDone] with whether it was right.
class ExerciseView extends StatefulWidget {
  const ExerciseView({super.key, required this.exercise, required this.onDone, this.onAnswer});
  final Exercise exercise;
  final ValueChanged<bool> onDone;
  final ValueChanged<bool>? onAnswer;

  @override
  State<ExerciseView> createState() => _ExerciseViewState();
}

class _ExerciseViewState extends State<ExerciseView> {
  /// "Je ne sais pas": a miss that shows the answer, instead of guessing.
  static const _dunno = Option('');
  Option? picked;

  Exercise get ex => widget.exercise;

  @override
  void initState() {
    super.initState();
    if (ex.kind == Kind.listen || ex.kind == Kind.tones) play(ex.word);
  }

  void answer(Option o) {
    if (picked != null) return;
    o.correct ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() => picked = o);
    if (ex.kind == Kind.meaning || ex.kind == Kind.recall) play(ex.word);
    widget.onAnswer?.call(o.correct);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final w = ex.word;
    final hint = store.hints;
    final question = switch (ex.kind) {
      Kind.meaning => 'Que veut dire ce mot ?',
      Kind.recall => 'Comment dit-on…',
      Kind.listen => 'Écoutez : que veut dire ce mot ?',
      Kind.tones => 'Quels sont les bons tons ?',
    };
    final listenButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          iconSize: 40,
          padding: const EdgeInsets.all(18),
          tooltip: 'Écouter',
          onPressed: () => play(w),
          icon: const Icon(Icons.volume_up_rounded),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: 'Écouter lentement',
          onPressed: () => play(w, slow: true),
          icon: const Icon(Icons.slow_motion_video),
        ),
      ],
    );
    final prompt = switch (ex.kind) {
      Kind.meaning => Column(
        children: [
          FittedBox(child: Hanzi(w.hanzi, w.roman, size: 64, weight: FontWeight.w600)),
          if (hint) ...[const SizedBox(height: 4), Pronunciation(w, size: 20)],
        ],
      ),
      Kind.recall => Text('« ${w.fr} »', textAlign: TextAlign.center, style: tt.headlineSmall),
      Kind.listen => listenButtons,
      Kind.tones => Column(
        children: [
          FittedBox(child: Hanzi(w.hanzi, w.roman, size: 56, weight: FontWeight.w600, toneColors: false)),
          const SizedBox(height: 12),
          listenButtons,
        ],
      ),
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Text(question, style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  child: Center(child: prompt),
                ),
              ),
              const SizedBox(height: 20),
              for (final o in ex.options) ...[
                _OptionTile(
                  option: o,
                  kind: ex.kind,
                  state: picked == null
                      ? null
                      : o.correct
                      ? true
                      : o == picked
                      ? false
                      : null,
                  revealed: picked != null,
                  onTap: () => answer(o),
                ),
                const SizedBox(height: 10),
              ],
              if (picked == null)
                Center(
                  child: TextButton.icon(
                    onPressed: () => answer(_dunno),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Je ne sais pas'),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: picked == null
              ? const SizedBox(width: double.infinity)
              : _Feedback(ex, picked!.correct, widget.onDone, unknown: picked == _dunno),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.kind,
    required this.state,
    required this.revealed,
    required this.onTap,
  });
  final Option option;
  final Kind kind;
  final bool? state; // true = the right answer, false = the wrong pick
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final success = context.palette.success;
    final (bg, fg, border) = switch (state) {
      true => (success.container, success.onContainer, success.color),
      false => (cs.errorContainer, cs.onErrorContainer, cs.error),
      null => (
        cs.surfaceContainerLow,
        cs.onSurface,
        revealed ? cs.outlineVariant.withValues(alpha: 0.5) : cs.outlineVariant,
      ),
    };
    final w = option.word;
    final label = switch (kind) {
      Kind.recall => Hanzi(option.text, w?.roman ?? '', size: 26, weight: FontWeight.w500, color: fg),
      Kind.tones => Roman(
        option.text,
        style: tt.titleLarge?.copyWith(color: fg),
        toneColors: revealed,
      ),
      _ => Text(option.text, style: tt.titleMedium?.copyWith(color: fg)),
    };
    final detail = w == null
        ? null
        : switch (kind) {
            Kind.recall => '${w.roman} · ${w.fr}',
            Kind.tones => w.fr,
            _ => '${w.hanzi} · ${w.roman}',
          };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: state == null ? 1 : 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(alignment: Alignment.centerLeft, child: label),
                      if (kind == Kind.recall && store.hints && !revealed && w != null)
                        Text(pronLine(w), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      if (revealed && detail != null) Text(detail, style: script(13, color: fg.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                if (state != null) Icon(state! ? Icons.check_circle : Icons.cancel, color: border),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback(this.ex, this.correct, this.onDone, {this.unknown = false});
  final Exercise ex;
  final bool correct, unknown;
  final ValueChanged<bool> onDone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final success = context.palette.success;
    final (bg, fg, button) = correct
        ? (success.container, success.onContainer, success.color)
        : (cs.errorContainer, cs.onErrorContainer, cs.error);
    final w = ex.word;
    return Material(
      color: bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(correct ? Icons.check_circle : Icons.info, color: fg),
                  const SizedBox(width: 8),
                  Text(
                    correct
                        ? 'Bien joué !'
                        : unknown
                        ? 'La réponse était'
                        : 'Pas tout à fait',
                    style: tt.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Réécouter',
                    onPressed: () => play(w),
                    icon: Icon(Icons.volume_up_rounded, color: fg),
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  style: tt.bodyLarge?.copyWith(color: fg),
                  children: [
                    TextSpan(
                      text: w.hanzi,
                      style: script(20, color: fg, weight: FontWeight.w600),
                    ),
                    TextSpan(text: '  ${w.roman}\n${w.fr}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: button,
                  foregroundColor: correct ? success.onColor : cs.onError,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => onDone(correct),
                child: const Text('Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
