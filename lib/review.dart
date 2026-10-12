import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'details.dart';
import 'store.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.go});
  final ValueChanged<int> go;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<Word> queue = store.sessionQueue();
  late final int total = queue.length;
  int done = 0;
  bool revealed = false;

  @override
  void initState() {
    super.initState();
    prefetch(queue.take(2));
  }

  void reveal() {
    setState(() => revealed = true);
    play(queue.first);
  }

  void grade(Grade g) {
    final w = queue.removeAt(0);
    HapticFeedback.selectionClick();
    setState(() {
      revealed = false;
      g == Grade.again ? queue.add(w) : done++;
    });
    store.grade(w, g);
    prefetch(queue.take(2));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🎉', style: tt.displayLarge),
              const SizedBox(height: 16),
              Text(total == 0 ? 'Tout est à jour !' : 'Session terminée !', style: tt.headlineSmall),
              const SizedBox(height: 8),
              Text(
                total == 0 ? 'Revenez plus tard pour vos prochaines révisions.' : '$total cartes révisées. 真讚！',
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => widget.go(2),
                icon: const Icon(Icons.quiz),
                label: const Text('Faire un quiz'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => widget.go(4),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Leçon sur mesure avec Claude'),
              ),
            ],
          ),
        ),
      );
    }

    final w = queue.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Text('${queue.length}', style: tt.labelLarge),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              onTap: revealed ? null : reveal,
              child: Card(
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text(langs[w.lang]!, style: zh(13)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: w.lang == 'hok' ? cs.primaryContainer : cs.secondaryContainer,
                            ),
                            Chip(label: Text(w.tag), visualDensity: VisualDensity.compact),
                            if (w.isNew)
                              Chip(
                                label: const Text('Nouveau'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: cs.tertiaryContainer,
                              ),
                          ],
                        ),
                        const Spacer(),
                        FittedBox(
                          child: Text(w.hanzi, style: zh(80, weight: FontWeight.w600)),
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 250),
                          crossFadeState: revealed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          firstChild: Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text('Touchez pour révéler', style: tt.bodyMedium?.copyWith(color: cs.outline)),
                          ),
                          secondChild: Column(
                            children: [
                              const SizedBox(height: 12),
                              Text(
                                w.roman,
                                textAlign: TextAlign.center,
                                style: tt.headlineSmall?.copyWith(color: cs.primary),
                              ),
                              if (w.zhuyin.isNotEmpty) Text(w.zhuyin, style: zh(18, color: cs.onSurfaceVariant)),
                              const Divider(height: 32, indent: 40, endIndent: 40),
                              Text(w.meaning, textAlign: TextAlign.center, style: zh(20)),
                              if (w.see.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'En ${langNames[w.lang == 'hok' ? 'man' : 'hok']!.toLowerCase()} : ${w.see}',
                                  textAlign: TextAlign.center,
                                  style: zh(15, color: cs.onSurfaceVariant),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (w.hasAudio)
                                    IconButton.filledTonal(
                                      onPressed: () => play(w),
                                      icon: const Icon(Icons.volume_up_rounded),
                                    ),
                                  if (w.moe != 0)
                                    TextButton.icon(
                                      onPressed: () => showWordSheet(context, w),
                                      icon: const Icon(Icons.menu_book_outlined),
                                      label: const Text('Exemples'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
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
                      for (final (g, label, color) in [
                        (Grade.again, 'Encore', cs.error),
                        (Grade.hard, 'Difficile', Colors.orange),
                        (Grade.good, 'Bien', Colors.green),
                        (Grade.easy, 'Facile', Colors.blue),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: color.withValues(alpha: 0.15),
                                foregroundColor: color,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size.fromHeight(64),
                              ),
                              onPressed: () => grade(g),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(
                                    formatInterval(nextInterval(w, g)),
                                    style: tt.labelSmall?.copyWith(color: color),
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
    );
  }
}
