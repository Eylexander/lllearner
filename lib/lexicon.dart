import 'package:flutter/material.dart';

import 'details.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Filter {
  all('Tous'),
  learned('Appris'),
  fresh('À apprendre'),
  weak('Difficiles');

  const _Filter(this.label);
  final String label;

  bool test(Word w) => switch (this) {
    all => true,
    learned => !w.isNew,
    fresh => w.isNew,
    weak => w.weak,
  };
}

class LexiconTab extends StatefulWidget {
  const LexiconTab({super.key});

  @override
  State<LexiconTab> createState() => _LexiconTabState();
}

class _LexiconTabState extends State<LexiconTab> {
  String q = '';
  _Filter filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = context.palette;
    final needle = plain(q.trim());
    final list = store.words
        .where((w) => filter.test(w) && (needle.isEmpty || w.hanzi.contains(q.trim()) || w.searchKey.contains(needle)))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            hintText: 'Caractères, pinyin ou français',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.search_off,
                  title: 'Aucun mot',
                  message: filter == _Filter.all ? 'Essayez une autre recherche.' : 'Aucun mot dans ce filtre.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: list.length + 1,
                  itemBuilder: (context, i) {
                    if (i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          '${list.length} mots · listes TOCFL · traductions CFDICT (CC BY-SA 3.0, chine-informations.com) '
                          '· exemples Tatoeba (CC BY 2.0 FR, tatoeba.org)',
                          style: tt.labelSmall?.copyWith(color: cs.outline),
                        ),
                      );
                    }
                    final w = list[i];
                    return ListTile(
                      onTap: () => showWordSheet(context, w),
                      leading: SizedBox(
                        width: 88,
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Hanzi(w.hanzi, w.roman, size: 26, weight: FontWeight.w500),
                        ),
                      ),
                      title: Text(w.fr, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(pronLine(w), style: script(13, color: cs.onSurfaceVariant)),
                      trailing: w.isNew
                          ? null
                          : Icon(
                              w.mastered ? Icons.verified : Icons.timelapse,
                              size: 20,
                              color: w.mastered ? palette.success.color : palette.warning.color,
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
