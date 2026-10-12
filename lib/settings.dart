import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

/// Whether the platform provides wallpaper colors (Android 12+); set by the app.
bool dynamicColorAvailable = false;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Réglages')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final palette = context.palette;
        Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(s, style: tt.titleSmall?.copyWith(color: cs.primary)),
        );
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            header('Cours'),
            ListTile(
              leading: CourseAvatar(store.course),
              title: Text(store.course.name),
              subtitle: const Text('Changer de cours'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showCourseSheet(context),
            ),
            header('Apprentissage'),
            const ListTile(title: Text('Objectif quotidien'), subtitle: Text('Nouveaux mots à apprendre chaque jour')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GoalPicker(value: store.dailyGoal, onChanged: (n) => store.set(() => store.dailyGoal = n)),
            ),
            const ListTile(title: Text('Prononciation affichée')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<Pron>(
                segments: const [
                  ButtonSegment(value: Pron.pinyin, label: Text('Pinyin')),
                  ButtonSegment(value: Pron.zhuyin, label: Text('Zhuyin')),
                  ButtonSegment(value: Pron.both, label: Text('Les deux')),
                ],
                selected: {store.pron},
                onSelectionChanged: (s) => store.set(() => store.pron = s.first),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Couleurs des tons'),
              subtitle: Row(
                children: [
                  for (final (i, s) in ['1er', '2e', '3e', '4e', 'neutre'].indexed) ...[
                    Text(
                      s,
                      style: TextStyle(color: palette.tones[i], fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
              value: store.toneColors,
              onChanged: (v) => store.set(() => store.toneColors = v),
            ),
            SwitchListTile(
              title: const Text('Aide à la prononciation'),
              subtitle: Text('Afficher le ${store.course.romanization} dans les exercices'),
              value: store.hints,
              onChanged: (v) => store.set(() => store.hints = v),
            ),
            header('Voix'),
            ListTile(
              title: const Text('Vitesse'),
              subtitle: Slider(
                value: store.speechRate,
                min: 0.2,
                max: 0.6,
                divisions: 8,
                label: store.speechRate < 0.35
                    ? 'Lente'
                    : store.speechRate < 0.47
                    ? 'Normale'
                    : 'Rapide',
                onChanged: (v) => store.set(() => store.speechRate = v),
                onChangeEnd: (_) => speak(store.course.greetings.first.$1),
              ),
            ),
            const _VoiceTile(),
            header('Apparence'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Système')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Clair')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Sombre')),
                ],
                selected: {store.themeMode},
                onSelectionChanged: (s) => store.set(() => store.themeMode = s.first, appearance: true),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Couleurs du fond d’écran'),
              subtitle: Text(
                dynamicColorAvailable
                    ? 'Material You : l’app suit les couleurs du système'
                    : 'Nécessite Android 12 ou plus',
              ),
              value: store.dynamicColor && dynamicColorAvailable,
              onChanged: dynamicColorAvailable
                  ? (v) => store.set(() => store.dynamicColor = v, appearance: true)
                  : null,
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: store.dynamicColor && dynamicColorAvailable ? 0.38 : 1,
              child: IgnorePointer(
                ignoring: store.dynamicColor && dynamicColorAvailable,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (i, s) in seeds.indexed)
                        Tooltip(
                          message: s.name,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => store.set(() => store.seed = i, appearance: true),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: ColorScheme.fromSeed(
                                seedColor: s.color,
                                brightness: cs.brightness,
                              ).primary,
                              child: store.seed == i
                                  ? Icon(
                                      Icons.check,
                                      color: ColorScheme.fromSeed(
                                        seedColor: s.color,
                                        brightness: cs.brightness,
                                      ).onPrimary,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            header('À propos'),
            ListTile(
              title: const Text('Sources et licences'),
              subtitle: const Text(
                'Vocabulaire : listes TOCFL. Traductions : CFDICT (CC BY-SA 3.0, chine-informations.com). '
                'Exemples : Tatoeba (CC BY 2.0 FR, tatoeba.org). '
                'Code source : github.com/Eylexander/LLLearner. ',
              ),
              isThreeLine: true,
              onTap: () => showLicensePage(context: context, applicationName: 'LLLearner'),
            ),
          ],
        );
      },
    ),
  );
}

/// The daily goal: casual to intense.
class GoalPicker extends StatelessWidget {
  const GoalPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const goals = [(5, 'Détente'), (10, 'Régulier'), (20, 'Sérieux'), (30, 'Intense')];

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
    showSelectedIcon: false,
    segments: [
      for (final (n, label) in goals)
        ButtonSegment(
          value: n,
          label: Column(
            children: [
              Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
    style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8))),
  );
}

/// Whether the phone can speak the course language, with a way to install a voice.
class _VoiceTile extends StatelessWidget {
  const _VoiceTile();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: voiceInstalled(),
    builder: (context, snap) {
      final palette = context.palette;
      final ok = snap.data;
      return ListTile(
        leading: Icon(
          ok == false ? Icons.warning_amber : Icons.record_voice_over_outlined,
          color: ok == false ? palette.warning.color : null,
        ),
        title: Text(
          ok == null
              ? 'Voix ${store.course.native}…'
              : ok
              ? 'Voix ${store.course.native} installée'
              : 'Voix ${store.course.native} introuvable',
        ),
        subtitle: Text(
          ok == false
              ? 'Installez la voix « ${store.course.voice} » dans les réglages de synthèse vocale'
              : 'Touchez pour écouter, réglages de synthèse vocale',
        ),
        onTap: ok == false ? openTtsSettings : () => speak(store.course.greetings.first.$1),
        onLongPress: openTtsSettings,
        trailing: IconButton(
          tooltip: 'Réglages de synthèse vocale',
          icon: const Icon(Icons.open_in_new),
          onPressed: openTtsSettings,
        ),
      );
    },
  );
}
