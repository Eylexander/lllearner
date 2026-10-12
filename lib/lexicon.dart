import 'package:flutter/material.dart';

import 'details.dart';
import 'store.dart';

class LexiconScreen extends StatefulWidget {
  const LexiconScreen({super.key});

  @override
  State<LexiconScreen> createState() => _LexiconScreenState();
}

class _LexiconScreenState extends State<LexiconScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final needle = plain(q.trim());
    final list = store.words
        .where((w) => needle.isEmpty || w.hanzi.contains(needle) || w.searchKey.contains(needle))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: SearchBar(
            hintText: 'Rechercher : 漢字, tâi-lô, pinyin, français',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${list.length} mots · touchez pour écouter et voir les détails · mots, définitions, exemples et audio : 教育部臺灣台語常用詞辭典 (CC BY-ND 3.0 TW) · traductions via CFDICT (CC BY-SA 3.0, chine-informations.com)',
              style: tt.labelMedium?.copyWith(color: cs.outline),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final w = list[i];
              return ListTile(
                onTap: () {
                  play(w);
                  showWordSheet(context, w);
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: SizedBox(
                  width: 88,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(w.hanzi, style: zh(26, weight: FontWeight.w500)),
                  ),
                ),
                title: Text(w.meaning, style: zh(15), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (store.active.length > 1) langs[w.lang],
                    w.roman,
                    w.zhuyin,
                  ].where((s) => s!.isNotEmpty).join(' · '),
                  style: zh(13, color: cs.onSurfaceVariant),
                ),
                trailing: Icon(
                  Icons.circle,
                  size: 12,
                  color: w.isNew
                      ? cs.outlineVariant
                      : w.mastered
                      ? Colors.green
                      : Colors.orange,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
