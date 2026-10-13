import 'package:flutter/material.dart';

import 'pinyin.dart';
import 'store.dart';
import 'theme.dart';

/// A word taken apart: one tile per character (its reading in the word and its meaning), and
/// for the chosen character how it is built (pictogram, combined meanings, or meaning + sound)
/// from components that can be taken apart in turn, all in place.
class CharacterBreakdown extends StatefulWidget {
  const CharacterBreakdown(this.word, {super.key});
  final Word word;

  @override
  State<CharacterBreakdown> createState() => _CharacterBreakdownState();
}

class _CharacterBreakdownState extends State<CharacterBreakdown> {
  late final chars = [for (final c in widget.word.hanzi.characters) ?store.character(c)];

  /// The character being looked at, then each component opened from it.
  late List<String> trail = chars.length == 1 ? [chars.first.hanzi] : [];

  /// Each character's syllable in the word, when the pinyin splits one per character.
  late final List<String> sounds = () {
    final s = [
      for (final s in syllables(widget.word.roman))
        if (s.tone > 0) s.text,
    ];
    return s.length == widget.word.hanzi.characters.length ? s : const <String>[];
  }();

  void open(String c, {bool root = false}) => setState(() {
    if (root) {
      trail = trail.firstOrNull == c ? [] : [c];
    } else {
      trail = [...trail, c];
    }
  });

  @override
  Widget build(BuildContext context) {
    if (chars.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chars.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, c) in chars.indexed)
                () {
                  final sound = i < sounds.length ? sounds[i] : '';
                  final reading = readingFor(c, sound);
                  final selected = trail.firstOrNull == c.hanzi;
                  final tone = tones(sound).firstOrNull;
                  return Material(
                    color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 2),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => open(c.hanzi, root: true),
                      child: SizedBox(
                        width: 96,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                          child: Column(
                            children: [
                              Text(
                                c.hanzi,
                                style: script(
                                  30,
                                  weight: FontWeight.w600,
                                  color: tone != null && store.toneColors ? palette.tone(tone) : null,
                                ),
                              ),
                              Text(sound.isEmpty ? reading?.roman ?? '' : sound, style: tt.labelMedium),
                              Text(
                                _short(reading?.fr ?? ''),
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: trail.isEmpty
              ? const SizedBox(width: double.infinity)
              : _Composition(
                  trail,
                  sound: chars.length == 1 && sounds.isNotEmpty ? sounds.first : '',
                  onOpen: open,
                  onBack: (n) => setState(() => trail = trail.sublist(0, n + 1)),
                ),
        ),
      ],
    );
  }
}

/// The first sense, without notes: 'Envelopper ; empaqueter' → 'Envelopper'.
String _short(String fr) => fr.split(' ; ').first;

class _Composition extends StatelessWidget {
  const _Composition(this.trail, {required this.sound, required this.onOpen, required this.onBack});
  final List<String> trail;
  final String sound; // the reading to show first, for a one-character word
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = store.character(trail.last)!;
    final first = trail.length == 1 ? readingFor(c, sound) : null;
    final readings = [?first, ...c.readings.where((r) => r != first)];
    final (kind, explain) = switch (c.kind) {
      'pictophonetic' => ('Idéophonogramme', 'une partie donne le sens, l’autre le son'),
      'ideographic' => ('Idéogramme composé', 'le sens naît de la réunion de ses éléments'),
      'pictographic' => ('Pictogramme', 'le dessin stylisé de ce qu’il représente'),
      _ => ('', ''),
    };
    // Pictograms' "parts" are only strokes that look like other characters (馬 → 灬): not shown.
    final components = switch (c.kind) {
      'pictophonetic' => [
        if (c.semantic.isNotEmpty) (c.semantic, 'sens'),
        if (c.phonetic.isNotEmpty) (c.phonetic, 'son'),
      ],
      'pictographic' => const <(String, String)>[],
      _ => [for (final p in c.parts) (p, '')],
    };
    Widget chip(String p, String role) {
      final info = store.character(p);
      final r = info?.readings.firstOrNull;
      return ActionChip(
        onPressed: info == null ? null : () => onOpen(p),
        avatar: Text(
          p,
          style: script(18, weight: FontWeight.w600, color: cs.onSurface),
        ),
        label: Text(
          [
            if (role == 'son' && r != null) r.roman else if (r != null) _short(r.fr),
            if (role.isNotEmpty) role,
          ].join(' · '),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trail.length > 1)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, t) in trail.indexed) ...[
                  if (i > 0) Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: i == trail.length - 1 ? null : () => onBack(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(t, style: script(16, color: i == trail.length - 1 ? cs.onSurface : cs.primary)),
                    ),
                  ),
                ],
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.hanzi, style: script(44, weight: FontWeight.w600)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in readings.take(3))
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${r.roman}  ',
                              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                            ),
                            TextSpan(text: r.fr),
                          ],
                        ),
                        style: tt.bodyMedium,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (kind.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: kind,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' : $explain.'),
                ],
              ),
              style: tt.bodyMedium,
            ),
          ],
          if (components.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [for (final (p, role) in components) chip(p, role)]),
          ],
          // Make Me a Hanzi's hint, in English; for meaning + sound it only repeats the meaning part.
          if (c.hint.isNotEmpty && c.kind != 'pictophonetic') ...[
            const SizedBox(height: 8),
            Text(
              '« ${c.hint} » (en)',
              style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
