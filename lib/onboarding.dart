import 'package:flutter/material.dart';

import 'course.dart';
import 'settings.dart';
import 'store.dart';
import 'widgets.dart';

/// First launch: pick a course, a daily goal, how pronunciation is shown.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final pages = PageController();
  int page = 0;

  void next() {
    if (page == 2) {
      store.set(() => store.onboarded = true);
      return;
    }
    pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i <= page ? cs.primary : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: pages,
                  onPageChanged: (p) => setState(() => page = p),
                  children: const [_CoursePage(), _GoalPage(), _PronPage()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    if (page > 0)
                      TextButton(
                        onPressed: () =>
                            pages.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
                        child: const Text('Retour'),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                      onPressed: next,
                      child: Text(page == 2 ? 'C’est parti !' : 'Suivant'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.subtitle, required this.children});
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      children: [
        Text(title, style: tt.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: tt.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 28),
        ...children,
      ],
    );
  }
}

class _CoursePage extends StatelessWidget {
  const _CoursePage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Page(
      title: 'Bienvenue sur LLLearner',
      subtitle: 'Quelle langue voulez-vous apprendre ?',
      children: [
        for (final Course c in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: c == store.course ? cs.secondaryContainer : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: c == store.course ? cs.primary : cs.outlineVariant, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                leading: CourseAvatar(c, radius: 26),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(c.tagline),
                trailing: c == store.course ? Icon(Icons.check_circle, color: cs.primary) : null,
                onTap: () => store.setCourse(c),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Leçons courtes, répétition espacée et quiz sur ce que vous avez appris. Vous pourrez changer de cours '
          'à tout moment.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _GoalPage extends StatelessWidget {
  const _GoalPage();

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Votre objectif',
    subtitle: 'Combien de nouveaux mots par jour ? Mieux vaut peu, mais tous les jours.',
    children: [
      GoalPicker(value: store.dailyGoal, onChanged: (n) => store.set(() => store.dailyGoal = n)),
      const SizedBox(height: 16),
      Text(
        'Environ ${(store.dailyGoal * 1.5).round()} minutes par jour, révisions comprises.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

class _PronPage extends StatelessWidget {
  const _PronPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sample = Word(store.course.id, '你好', 'nǐ hǎo', 'Bonjour', '', zhuyin: 'ㄋㄧˇ ㄏㄠˇ');
    return _Page(
      title: 'La prononciation',
      subtitle: 'Le pinyin utilise l’alphabet latin ; le zhuyin (ㄅㄆㄇ) est le système utilisé à Taïwan.',
      children: [
        SegmentedButton<Pron>(
          segments: const [
            ButtonSegment(value: Pron.pinyin, label: Text('Pinyin')),
            ButtonSegment(value: Pron.zhuyin, label: Text('Zhuyin')),
            ButtonSegment(value: Pron.both, label: Text('Les deux')),
          ],
          selected: {store.pron},
          onSelectionChanged: (s) => store.set(() => store.pron = s.first),
        ),
        const SizedBox(height: 20),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => play(sample),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Hanzi(sample.hanzi, sample.roman, size: 56, weight: FontWeight.w600),
                  Pronunciation(sample, size: 24),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volume_up_outlined, color: cs.primary, size: 18),
                      const SizedBox(width: 6),
                      Text('Touchez pour écouter', style: TextStyle(color: cs.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Couleurs des tons'),
          subtitle: const Text('Chaque ton a sa couleur, pour mieux les retenir'),
          value: store.toneColors,
          onChanged: (v) => store.set(() => store.toneColors = v),
        ),
        FutureBuilder(
          future: voiceInstalled(),
          builder: (context, snap) => snap.data == false
              ? Card(
                  color: cs.tertiaryContainer,
                  child: ListTile(
                    leading: Icon(Icons.record_voice_over_outlined, color: cs.onTertiaryContainer),
                    title: Text(
                      'Installez la voix ${store.course.native}',
                      style: TextStyle(color: cs.onTertiaryContainer),
                    ),
                    subtitle: Text(
                      'L’audio utilise la synthèse vocale du téléphone. Ajoutez la voix « ${store.course.voice} ».',
                      style: TextStyle(color: cs.onTertiaryContainer),
                    ),
                    onTap: openTtsSettings,
                  ),
                )
              : const SizedBox(),
        ),
      ],
    );
  }
}
