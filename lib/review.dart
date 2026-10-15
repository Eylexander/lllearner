import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lesson.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

/// The "Réviser" tab: what's due, how the learner is doing, what's coming.
class ReviewTab extends StatelessWidget {
  const ReviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = context.palette;
    final learned = store.learned.toList();
    if (learned.isEmpty) {
      final next = store.nextLesson;
      return EmptyState(
        icon: Icons.style_outlined,
        title: 'Rien à réviser pour l’instant',
        message:
            'Les mots appris en leçon reviennent ici juste avant que vous ne les oubliiez : '
            'c’est la répétition espacée.',
        actions: [
          if (next != null)
            FilledButton.icon(
              onPressed: () => LessonPage.open(context, next),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Faire ma première leçon'),
            ),
        ],
      );
    }
    final due = store.due.length;
    final mastered = learned.where((w) => w.mastered).length;
    final forecast = store.forecast();
    final peak = forecast.fold(1, (a, b) => a > b ? a : b);
    final soonest = learned
        .where((w) => w.due!.isAfter(DateTime.now()))
        .map((w) => w.due!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          color: due > 0 ? cs.primaryContainer : cs.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$due',
                  style: tt.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: due > 0 ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
                Text(
                  due > 0
                      ? 'carte${due > 1 ? 's' : ''} à réviser maintenant'
                      : 'Tout est à jour !${soonest == null ? '' : ' Prochaine révision ${_when(soonest)}.'}',
                  style: tt.titleMedium?.copyWith(color: due > 0 ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (due > 0)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => ReviewSession.open(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Commencer la révision'),
                  )
                else
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => ReviewSession.open(context, ahead: true),
                    icon: const Icon(Icons.fast_forward_rounded),
                    label: const Text('Réviser en avance'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat('Appris', learned.length, cs.primary),
            const SizedBox(width: 12),
            _Stat('En cours', learned.length - mastered, palette.warning.color),
            const SizedBox(width: 12),
            _Stat('Maîtrisés', mastered, palette.success.color),
          ],
        ),
        const SizedBox(height: 24),
        Text('Les 7 prochains jours', style: tt.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, n) in forecast.indexed)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('$n', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Container(
                            height: 70 * n / peak + 2,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: i == 0 ? cs.primary : cs.secondary.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_day(i), style: tt.labelSmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: cs.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: cs.tertiary),
                    const SizedBox(width: 8),
                    Text('Comment noter une carte', style: tt.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Essayez de vous rappeler le sens et la prononciation avant de retourner la carte, puis soyez '
                  'honnête : « Encore » si vous aviez oublié, « Difficile » si ça a été laborieux, « Bien » si '
                  'c’était juste, « Facile » si c’était immédiat. L’app espace les révisions en conséquence.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _day(int i) => switch (i) {
    0 => 'Auj.',
    1 => 'Dem.',
    _ => const [
      'lun.',
      'mar.',
      'mer.',
      'jeu.',
      'ven.',
      'sam.',
      'dim.',
    ][DateTime.now().add(Duration(days: i)).weekday - 1],
  };

  static String _when(DateTime d) {
    final diff = d.difference(DateTime.now());
    return diff.inMinutes < 60
        ? 'dans ${diff.inMinutes + 1} min'
        : diff.inHours < 24
        ? 'dans ${diff.inHours} h'
        : 'dans ${diff.inDays + 1} j';
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(
                '$value',
                style: tt.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
              Text(label, style: tt.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flashcards for the due words, or with [ahead] for the next ones to come up: recall, reveal,
/// grade. Each grade is saved at once.
class ReviewSession extends StatefulWidget {
  const ReviewSession({super.key, this.ahead = false});
  final bool ahead;

  static Future<void> open(BuildContext context, {bool ahead = false}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewSession(ahead: ahead)));

  @override
  State<ReviewSession> createState() => _ReviewSessionState();
}

class _ReviewSessionState extends State<ReviewSession> {
  late final List<Word> queue = widget.ahead ? store.ahead() : store.due;
  late final int total = queue.length;
  int done = 0;
  bool revealed = false;

  void reveal() {
    setState(() => revealed = true);
    play(queue.first);
  }

  void grade(Grade g) {
    final w = queue.removeAt(0);
    tts.stop();
    HapticFeedback.selectionClick();
    setState(() {
      revealed = false;
      g == Grade.again ? queue.add(w) : done++;
    });
    store.grade(w, g);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = context.palette;

    if (queue.isEmpty) {
      // Keep going: cards that came due meanwhile first, then the next ones ahead of time.
      final more = store.due.isNotEmpty;
      final canAhead = store.learned.isNotEmpty;
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.task_alt,
          title: total == 0 ? 'Tout est à jour !' : 'Révision terminée !',
          message: total == 0
              ? 'Revenez plus tard.'
              : '$total carte${total > 1 ? 's' : ''} révisée${total > 1 ? 's' : ''}. ${store.course.bravo}',
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Terminer')),
            if (more || canAhead)
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReviewSession(ahead: !more))),
                icon: const Icon(Icons.fast_forward_rounded),
                label: Text(more ? 'Continuer la révision' : 'Réviser en avance'),
              ),
          ],
        ),
      );
    }

    final w = queue.first;
    final example = revealed ? store.examples(w).firstOrNull : null;
    return Scaffold(
      appBar: SessionBar(
        progress: total == 0 ? 0 : done / total,
        trailing: Center(child: Text('${queue.length}', style: tt.labelLarge)),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: revealed ? null : reveal,
                  child: Card(
                    child: SizedBox(
                      width: double.infinity,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              revealed ? w.tag : 'Vous souvenez-vous de ce mot ?',
                              style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 32),
                            FittedBox(
                              child: Hanzi(w.hanzi, w.roman, size: 80, weight: FontWeight.w600, toneColors: revealed),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              child: !revealed
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Text(
                                        'Touchez la carte pour voir la réponse',
                                        style: tt.bodyMedium?.copyWith(color: cs.outline),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        const SizedBox(height: 8),
                                        Pronunciation(w, size: 24),
                                        const SizedBox(height: 8),
                                        IconButton.filledTonal(
                                          tooltip: 'Écouter',
                                          onPressed: () => play(w),
                                          icon: const Icon(Icons.volume_up_rounded),
                                        ),
                                        const Divider(height: 32),
                                        Text(w.fr, textAlign: TextAlign.center, style: tt.headlineSmall),
                                        if (example != null) ...[
                                          const SizedBox(height: 20),
                                          ExampleTile(example, highlight: w.hanzi),
                                        ],
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 64,
                child: revealed
                    ? Row(
                        children: [
                          for (final (g, label, bg, fg) in [
                            (Grade.again, 'Encore', cs.errorContainer, cs.onErrorContainer),
                            (Grade.hard, 'Difficile', palette.warning.container, palette.warning.onContainer),
                            (Grade.good, 'Bien', palette.success.container, palette.success.onContainer),
                            (Grade.easy, 'Facile', cs.primaryContainer, cs.onPrimaryContainer),
                          ])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: bg,
                                    foregroundColor: fg,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size.fromHeight(64),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: () => grade(g),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(
                                        formatInterval(nextInterval(w, g, DateTime.now())),
                                        style: tt.labelSmall?.copyWith(color: fg),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : FilledButton(
                        onPressed: reveal,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                        child: const Text('Afficher la réponse'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
