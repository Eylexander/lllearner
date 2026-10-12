import 'dart:math';

import 'package:flutter/material.dart';

import 'store.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.go});
  final ValueChanged<int> go;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final (greet, greetFr) = hour < 12
        ? ('早安', 'Tsá-an · Bonjour')
        : hour < 18
        ? ('午安', 'Ngóo-an · Bon après-midi')
        : ('暗安', 'Àm-an · Bonsoir');
    final words = store.words;
    final todo = store.due.length + min(store.newLeftToday, words.where((w) => w.isNew).length);
    final mastered = words.where((w) => w.mastered).length;
    final learning = words.where((w) => !w.isNew).length - mastered;
    // Word of the day: among studied words and today's new ones, not the whole deck.
    final pool = [...words.where((w) => !w.isNew), ...store.sessionQueue().where((w) => w.isNew)];
    final daily = (pool.isEmpty ? words : pool)[DateTime.now().difference(DateTime(2024)).inDays % max(1, pool.length)];
    final tags = <String, List<Word>>{};
    for (final w in words) {
      (tags[store.active.length > 1 ? '${langs[w.lang]} · ${w.tag}' : w.tag] ??= []).add(w);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greet,
                    style: zh(36, weight: FontWeight.w700, color: cs.primary),
                  ),
                  Text(greetFr, style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(99)),
              child: Text('🔥 ${store.streak} j', style: tt.titleMedium?.copyWith(color: cs.onTertiaryContainer)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          color: cs.primary,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => go(1),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$todo',
                          style: tt.displayMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          todo == 0 ? 'Rien à réviser, bravo !' : 'cartes à réviser aujourd’hui',
                          style: tt.titleMedium?.copyWith(color: cs.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.onPrimary,
                    child: Icon(todo == 0 ? Icons.quiz : Icons.play_arrow_rounded, color: cs.primary, size: 32),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat('Nouveaux', words.where((w) => w.isNew).length, cs.secondary),
            const SizedBox(width: 12),
            _Stat('En cours', learning, Colors.orange),
            const SizedBox(width: 12),
            _Stat('Maîtrisés', mastered, Colors.green),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('Nouveaux mots / jour', style: tt.titleSmall)),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final n in const [5, 10, 20, 30]) ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {store.newPerDay},
              onSelectionChanged: (s) => store.setNewPerDay(s.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Langues étudiées', style: tt.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
                multiSelectionEnabled: true,
                segments: [
                  for (final MapEntry(key: code, value: name) in langs.entries)
                    ButtonSegment(
                      value: code,
                      label: Text('$name ${langNames[code]}', style: zh(13)),
                    ),
                ],
                selected: store.active,
                onSelectionChanged: store.setActive, // ignores an empty selection
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Mot du jour', style: tt.titleLarge),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => play(daily),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(daily.hanzi, style: zh(44, weight: FontWeight.w600)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${langs[daily.lang]} · ${daily.roman}', style: zh(16, color: cs.primary)),
                        Text(daily.meaning, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (daily.hasAudio) Icon(Icons.volume_up_rounded, color: cs.primary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('Par thème', style: tt.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (final MapEntry(key: tag, value: list) in tags.entries) ...[
                  Row(
                    children: [
                      Expanded(child: Text(tag, style: tt.titleSmall)),
                      Text('${list.where((w) => !w.isNew).length}/${list.length}', style: tt.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: list.where((w) => !w.isNew).length / list.length,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
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
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
