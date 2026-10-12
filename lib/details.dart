import 'package:flutter/material.dart';

import 'store.dart';

/// Bottom sheet with everything known about a word: romanization, meaning, the other
/// language's equivalent, and (hok) the MOE dictionary's definitions and example sentences.
void showWordSheet(BuildContext context, Word w) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final defs = store.definitions(w);
    final examples = store.examples(w);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Row(
            children: [
              Flexible(
                child: Text(w.hanzi, style: zh(44, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Chip(
                label: Text(langs[w.lang]!, style: zh(13)),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              if (w.hasAudio)
                IconButton.filledTonal(onPressed: () => play(w), icon: const Icon(Icons.volume_up_rounded)),
            ],
          ),
          Text(w.roman, style: tt.titleLarge?.copyWith(color: cs.primary)),
          if (w.zhuyin.isNotEmpty) Text(w.zhuyin, style: zh(16, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (w.fr.isNotEmpty) Text(w.fr, style: tt.titleMedium),
          if (w.see.isNotEmpty)
            Text('En ${langNames[w.lang == 'hok' ? 'man' : 'hok']!.toLowerCase()} : ${w.see}', style: zh(15)),
          if (defs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Définition (華語, dictionnaire du ministère)', style: tt.labelLarge?.copyWith(color: cs.outline)),
            const SizedBox(height: 4),
            Text(defs, style: zh(15)),
          ],
          if (examples.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Exemples', style: tt.labelLarge?.copyWith(color: cs.outline)),
            for (final (i, e) in examples.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.hanji, style: zh(17)),
                subtitle: Text('${e.roman}\n華語：${e.zh}', style: zh(13, color: cs.onSurfaceVariant)),
                isThreeLine: true,
                trailing: IconButton(onPressed: () => playExample(w, i), icon: const Icon(Icons.volume_up_outlined)),
              ),
          ],
        ],
      ),
    );
  },
);
