import 'package:flutter/material.dart';

import 'characters.dart';
import 'course.dart';
import 'details.dart';
import 'pinyin.dart';
import 'settings.dart';
import 'store.dart';
import 'theme.dart';

final _han = RegExp(r'\p{Script=Han}', unicode: true);

/// Characters, each colored by its tone when tone colors are on and the pinyin has one
/// syllable per character. [toneColors] false hides them (tone exercises).
class Hanzi extends StatelessWidget {
  const Hanzi(this.text, this.roman, {super.key, required this.size, this.weight, this.toneColors = true, this.color});
  final String text, roman;
  final double size;
  final FontWeight? weight;
  final bool toneColors;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = script(size, weight: weight, color: color);
    final t = tones(roman);
    if (!toneColors || !store.toneColors || !store.course.hasTones || _han.allMatches(text).length != t.length) {
      return Text(text, style: style, textAlign: TextAlign.center);
    }
    final palette = context.palette;
    var i = 0;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final c in text.characters)
            TextSpan(
              text: c,
              style: _han.hasMatch(c) ? TextStyle(color: palette.tone(t[i++])) : null,
            ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Pinyin with each syllable in its tone's color; other romanizations as they are.
class Roman extends StatelessWidget {
  const Roman(this.roman, {super.key, this.style, this.textAlign, this.toneColors = true});
  final String roman;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool toneColors;

  @override
  Widget build(BuildContext context) {
    if (!toneColors || !store.toneColors || !store.course.hasTones) {
      return Text(roman, style: style, textAlign: textAlign);
    }
    final palette = context.palette;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final s in syllables(roman))
            TextSpan(
              text: s.text,
              style: TextStyle(color: palette.tone(s.tone)),
            ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

/// Zhuyin, each syllable in its tone's color (ˊ 2, ˇ 3, ˋ 4, ˙ neutral, unmarked 1).
class Zhuyin extends StatelessWidget {
  const Zhuyin(this.zhuyin, {super.key, required this.size, this.textAlign});
  final String zhuyin;
  final double size;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final style = script(size, color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (!store.toneColors) return Text(zhuyin, style: style, textAlign: textAlign);
    final palette = context.palette;
    int tone(String s) => s.contains('˙')
        ? 5
        : s.contains('ˊ')
        ? 2
        : s.contains('ˇ')
        ? 3
        : s.contains('ˋ')
        ? 4
        : 1;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (i, s) in zhuyin.split(' ').indexed)
            TextSpan(
              text: i == 0 ? s : ' $s',
              style: TextStyle(color: palette.tone(tone(s))),
            ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

/// A word's pronunciation as the learner chose to see it: pinyin, zhuyin or both.
class Pronunciation extends StatelessWidget {
  const Pronunciation(this.word, {super.key, this.size = 20, this.align = TextAlign.center});
  final Word word;
  final double size;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zhuyin = word.zhuyin.isNotEmpty && store.pron != Pron.pinyin;
    final pinyin = !zhuyin || store.pron == Pron.both;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (pinyin)
          Roman(
            word.roman,
            textAlign: align,
            style: TextStyle(fontSize: size, color: cs.primary, fontWeight: FontWeight.w500),
          ),
        if (zhuyin) Zhuyin(word.zhuyin, size: pinyin ? size * 0.8 : size, textAlign: align),
      ],
    );
  }
}

/// One line for lists: pinyin or zhuyin as chosen.
String pronLine(Word w) => switch (store.pron) {
  Pron.zhuyin when w.zhuyin.isNotEmpty => w.zhuyin,
  Pron.both when w.zhuyin.isNotEmpty => '${w.roman} · ${w.zhuyin}',
  _ => w.roman,
};

class CourseAvatar extends StatelessWidget {
  const CourseAvatar(this.course, {super.key, this.radius = 18});
  final Course course;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      child: Text(
        course.badge,
        style: TextStyle(
          fontSize: radius,
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          locale: course.locale,
        ),
      ),
    );
  }
}

/// The course picker, as in big language apps: every course with its progress.
void showCourseSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  builder: (context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Mes cours', style: tt.titleLarge),
          ),
          for (final c in courses)
            ListTile(
              leading: CourseAvatar(c, radius: 22),
              title: Text(c.name),
              subtitle: Text(c.tagline),
              trailing: c == store.course ? Icon(Icons.check_circle, color: cs.primary) : null,
              selected: c == store.course,
              onTap: () {
                store.setCourse(c);
                Navigator.pop(context);
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Text(
              'Chaque cours a sa propre progression. D’autres langues pourront s’ajouter ici.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Réglages'),
            onTap: () {
              final nav = Navigator.of(context)..pop();
              SettingsPage.open(nav.context);
            },
          ),
        ],
      ),
    );
  },
);

/// The course switcher shown in the top app bar.
class CourseButton extends StatelessWidget {
  const CourseButton({super.key});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(24),
    onTap: () => showCourseSheet(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CourseAvatar(store.course),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              store.course.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );
}

/// Days in a row: lit up once something was done today.
class StreakChip extends StatelessWidget {
  const StreakChip({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final streak = context.palette.streak;
    final lit = store.activeToday;
    return Tooltip(
      message: 'Série de jours',
      child: Material(
        color: lit ? streak.container : cs.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showStreakSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  lit ? Icons.local_fire_department : Icons.local_fire_department_outlined,
                  size: 20,
                  color: lit ? streak.onContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${store.streak}',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: lit ? streak.onContainer : cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

void showStreakSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  builder: (context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final streak = context.palette.streak;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final active = store.days.toSet();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 56, color: store.activeToday ? streak.color : cs.outline),
            Text(
              store.streak == 0
                  ? 'Pas encore de série'
                  : '${store.streak} jour${store.streak > 1 ? 's' : ''} d’affilée',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              store.activeToday
                  ? 'Bravo, la série continue demain !'
                  : 'Faites une leçon, une révision ou un quiz aujourd’hui pour l’entretenir.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 7; i++)
                  () {
                    final day = monday.add(Duration(days: i));
                    final done = active.contains(day.toIso8601String().substring(0, 10));
                    final today = i == now.weekday - 1;
                    return Column(
                      children: [
                        Text(_weekdays[i], style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? streak.container : null,
                            border: today ? Border.all(color: done ? streak.color : cs.outline, width: 2) : null,
                          ),
                          child: done
                              ? Icon(Icons.check, size: 20, color: streak.onContainer)
                              : Center(child: Text('${day.day}', style: tt.labelMedium)),
                        ),
                      ],
                    );
                  }(),
              ],
            ),
          ],
        ),
      ),
    );
  },
);

/// Icon, title, message and an optional action, centered: for empty or finished screens.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actions = const []});
  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: cs.onSecondaryContainer),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: tt.headlineSmall),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
            ],
          ],
        ),
      ),
    );
  }
}

/// Session progress at the top of lessons, reviews and quizzes, with a close button.
class SessionBar extends StatelessWidget implements PreferredSizeWidget {
  const SessionBar({super.key, required this.progress, this.trailing});
  final double progress;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: 64,
    leading: IconButton(
      tooltip: 'Quitter',
      icon: const Icon(Icons.close),
      onPressed: () => Navigator.maybePop(context),
    ),
    titleSpacing: 0,
    title: TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0, 1)),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, v, _) =>
          LinearProgressIndicator(value: v, minHeight: 10, borderRadius: BorderRadius.circular(8)),
    ),
    actions: [
      if (trailing != null) Padding(padding: const EdgeInsets.only(left: 16), child: trailing),
      const SizedBox(width: 20),
    ],
  );
}

/// "Quit? Progress in this session is lost" before leaving a lesson half-way.
Future<bool> confirmQuit(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout),
        title: const Text('Quitter ?'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitter')),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuer')),
        ],
      ),
    ) ??
    false;

/// An example sentence: characters, pinyin, French. Each word of it is a box (the [highlight]ed
/// one in the primary color); tapping one selects it and opens it below the sentence, with its
/// characters taken apart, without leaving the page. The speaker or the translation reads it.
class ExampleTile extends StatefulWidget {
  const ExampleTile(this.example, {super.key, this.highlight = ''});
  final Example example;
  final String highlight;

  @override
  State<ExampleTile> createState() => _ExampleTileState();
}

class _ExampleTileState extends State<ExampleTile> {
  Word? selected;

  void select(Word w) {
    setState(() => selected = selected == w ? null : w);
    if (selected != null) play(w);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final e = widget.example, h = widget.highlight;
    final target = h.isEmpty ? null : store.byKey('${store.course.id}:$h');
    final segments = [
      for (final (i, p) in (h.isEmpty ? [e.hanzi] : e.hanzi.split(h)).indexed) ...[
        if (i > 0) (h, target, true),
        for (final (s, w) in store.segment(p)) (s, w, false),
      ],
    ];
    Widget box(String s, Word? w, bool isTarget) {
      final text = Text(
        s,
        style: script(20, color: isTarget ? cs.primary : null, weight: isTarget ? FontWeight.w700 : null),
      );
      if (w == null) return Padding(padding: const EdgeInsets.only(top: 2, bottom: 4), child: text);
      final on = w == selected;
      return Material(
        color: on ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => select(w),
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: on || isTarget ? cs.primary : cs.outlineVariant, width: on ? 3 : 2),
              ),
            ),
            child: text,
          ),
        ),
      );
    }

    final w = selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Écouter la phrase',
                visualDensity: VisualDensity.compact,
                onPressed: () => speak(e.hanzi),
                icon: Icon(Icons.volume_up_outlined, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 4, runSpacing: 6, children: [for (final (s, w, t) in segments) box(s, w, t)]),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => speak(e.hanzi),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (store.pron != Pron.zhuyin || !store.course.hasZhuyin)
                            Text(e.roman, style: tt.bodyMedium?.copyWith(color: cs.primary)),
                          Text(e.fr, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: w == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.primary, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Hanzi(w.hanzi, w.roman, size: 28, weight: FontWeight.w600),
                            const SizedBox(width: 10),
                            Expanded(child: Pronunciation(w, size: 16, align: TextAlign.start)),
                            IconButton(
                              tooltip: 'Écouter',
                              onPressed: () => play(w),
                              icon: const Icon(Icons.volume_up_rounded),
                            ),
                            IconButton(
                              tooltip: 'Tout sur ce mot',
                              onPressed: () => showWordSheet(context, w),
                              icon: const Icon(Icons.open_in_new),
                            ),
                            IconButton(
                              tooltip: 'Fermer',
                              onPressed: () => setState(() => selected = null),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 8),
                          child: Text(w.fr, style: tt.titleMedium),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CharacterBreakdown(w, key: ValueKey(w.key)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A circular progress indicator around a label.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.size, this.child, this.stroke = 6});
  final double value, size, stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: value.clamp(0, 1),
          strokeWidth: stroke,
          strokeCap: StrokeCap.round,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        if (child != null) Center(child: child),
      ],
    ),
  );
}
