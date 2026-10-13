import 'package:flutter/material.dart';

import 'characters.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bottom sheet with everything about a word: pronunciation, meaning, where it stands
/// in the learner's reviews, and example sentences.
void showWordSheet(BuildContext context, Word w) {
  play(w);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final palette = context.palette;
        final examples = store.examples(w);
        final (icon, status, color) = w.isNew
            ? (Icons.fiber_new_outlined, 'Pas encore appris', cs.onSurfaceVariant)
            : w.mastered
            ? (Icons.verified, 'Maîtrisé', palette.success.color)
            : (
                Icons.timelapse,
                w.due!.isAfter(DateTime.now()) ? 'En cours · prochaine révision le ${_date(w.due!)}' : 'À réviser',
                palette.warning.color,
              );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hanzi(w.hanzi, w.roman, size: 48, weight: FontWeight.w600),
                        Pronunciation(w, size: 22, align: TextAlign.start),
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
              const SizedBox(height: 12),
              Text(w.fr, style: tt.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(w.tag), visualDensity: VisualDensity.compact),
                  Chip(
                    avatar: Icon(icon, size: 18, color: color),
                    label: Text(status),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (w.isNew) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => store.markKnown(w),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Je le connais déjà'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Caractères', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              CharacterBreakdown(w),
              if (examples.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Exemples', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                for (final e in examples) ExampleTile(e, highlight: w.hanzi),
              ],
            ],
          ),
        );
      },
    ),
  );
}

String _date(DateTime d) =>
    '${d.day} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][d.month - 1]}';
