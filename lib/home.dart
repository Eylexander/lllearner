import 'package:flutter/material.dart';

import 'fiche.dart';
import 'lesson.dart';
import 'review.dart';
import 'store.dart';
import 'widgets.dart';

/// The "Apprendre" tab: today's goal, the next lesson, and the whole course path.
class LearnTab extends StatelessWidget {
  const LearnTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final (hanzi, roman, fr) =
        store.course.greetings[hour < 12
            ? 0
            : hour < 18
            ? 1
            : 2];
    final next = store.nextLesson;
    // Sections in course order, with their units.
    final sections = <String, List<Unit>>{};
    for (final u in store.units) {
      (sections[u.section] ??= []).add(u);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hanzi,
                style: script(30, weight: FontWeight.w700, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('$roman · $fr', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _TodayCard(next),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Votre parcours', style: tt.titleLarge),
        ),
        const SizedBox(height: 12),
        for (final MapEntry(key: name, value: units) in sections.entries) ...[
          _Section(name, units, current: next),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard(this.next);
  final Lesson? next;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = store.learnedToday, goal = store.dailyGoal;
    final due = store.due.length;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProgressRing(
                  value: done / goal,
                  size: 64,
                  child: done >= goal
                      ? Icon(Icons.check_rounded, color: cs.primary, size: 32)
                      : Text('$done/$goal', style: tt.titleSmall?.copyWith(color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        done >= goal ? 'Objectif du jour atteint !' : 'Objectif du jour',
                        style: tt.titleMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        done >= goal
                            ? '$done nouveaux mots aujourd’hui'
                            : '${goal - done} nouveau${goal - done > 1 ? 'x' : ''} mot${goal - done > 1 ? 's' : ''} '
                                  'à apprendre',
                        style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                      ),
                      if (due > 0)
                        Text(
                          '$due révision${due > 1 ? 's' : ''} en attente',
                          style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (next != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => LessonPage.open(context, next!),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  store.learned.isEmpty
                      ? 'Commencer · ${next!.unit.name}'
                      : 'Continuer · ${next!.unit.name}, leçon ${next!.number}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (next != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cs.onPrimaryContainer),
                onPressed: () => LessonFiche.open(context, next!),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Lire la fiche de la leçon d’abord'),
              )
            else
              Text('Vous avez appris tout le cours. 太厲害了！', style: tt.titleMedium, textAlign: TextAlign.center),
            if (due > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: cs.onPrimaryContainer,
                  side: BorderSide(color: cs.onPrimaryContainer.withValues(alpha: 0.4)),
                ),
                onPressed: () => ReviewSession.open(context),
                icon: const Icon(Icons.style_outlined),
                label: Text('Réviser $due carte${due > 1 ? 's' : ''}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A part of the course ('Les essentiels', 'Niveau 1 · Débutant'), open when it holds the
/// next lesson.
class _Section extends StatelessWidget {
  const _Section(this.name, this.units, {required this.current});
  final String name;
  final List<Unit> units;
  final Lesson? current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = units.fold(0, (n, u) => n + u.size);
    final learned = units.fold(0, (n, u) => n + u.learned);
    final here = units.contains(current?.unit);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(name),
        initiallyExpanded: here,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: ProgressRing(
          value: size == 0 ? 0 : learned / size,
          size: 40,
          stroke: 4,
          child: learned == size ? Icon(Icons.check, size: 20, color: cs.primary) : null,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$learned / $size mots'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [for (final u in units) _UnitView(u, current: current)],
      ),
    );
  }
}

class _UnitView extends StatelessWidget {
  const _UnitView(this.unit, {required this.current});
  final Unit unit;
  final Lesson? current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(unit.name, style: tt.titleSmall)),
              Text('${unit.learned}/${unit.size}', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final l in unit.lessons) _LessonButton(l, current: l == current)],
          ),
        ],
      ),
    );
  }
}

class _LessonButton extends StatelessWidget {
  const _LessonButton(this.lesson, {required this.current});
  final Lesson lesson;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = lesson.done;
    final (bg, fg) = done
        ? (cs.primary, cs.onPrimary)
        : current || lesson.learned > 0
        ? (cs.primaryContainer, cs.onPrimaryContainer)
        : (cs.surfaceContainerHighest, cs.onSurfaceVariant);
    final preview = lesson.words.take(3).map((w) => w.hanzi).join(' ');
    return Tooltip(
      message: '${done ? 'Revoir' : 'Leçon ${lesson.number}'} · $preview',
      child: Material(
        color: bg,
        shape: CircleBorder(side: current ? BorderSide(color: cs.primary, width: 3) : BorderSide.none),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => LessonFiche.open(context, lesson),
          child: SizedBox.square(
            dimension: current ? 52 : 44,
            child: Center(
              child: done
                  ? Icon(Icons.check_rounded, color: fg)
                  : current
                  ? Icon(Icons.play_arrow_rounded, color: fg, size: 30)
                  : Text(
                      '${lesson.number}',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
