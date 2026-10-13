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
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Choisir la voix'),
              subtitle: Text(store.voice?['name'] ?? 'Voix par défaut du téléphone'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showVoices(context),
            ),
            header('Rappel'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Rappel quotidien'),
              subtitle: Text(
                store.reminder
                    ? 'Chaque jour à ${_time(store.reminderAt)}, sauf si vous avez déjà pratiqué et qu’aucune '
                          'révision n’attend'
                    : 'Une notification pour ne pas oublier vos révisions',
              ),
              value: store.reminder,
              onChanged: (v) {
                store.set(() => store.reminder = v);
                syncReminder(ask: v);
              },
            ),
            ListTile(
              enabled: store.reminder,
              leading: const Icon(Icons.schedule),
              title: const Text('Heure du rappel'),
              trailing: Text(_time(store.reminderAt), style: tt.titleMedium),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: store.reminderAt ~/ 60, minute: store.reminderAt % 60),
                  builder: (context, child) =>
                      MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
                );
                if (t == null) return;
                store.set(() => store.reminderAt = t.hour * 60 + t.minute);
                syncReminder();
              },
            ),
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
                'Formation des caractères : Make Me a Hanzi (LGPL 3, github.com/skishore/makemeahanzi). '
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

String _time(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// The course language's voices on the phone: Google's Taiwan voices differ, some handle tones
/// better. Picking one reads a sample, so they can be compared.
void _showVoices(BuildContext context) {
  final sample = store.course.sentenceHint.split(' / ').first;
  void pick(Map<String, String>? v) {
    store.set(() => store.voice = v == null ? null : {'name': v['name']!, 'locale': v['locale']!});
    speak(sample);
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => FutureBuilder(
      future: courseVoices(),
      builder: (context, snap) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final voices = snap.data ?? const [];
          Widget tile(String title, String subtitle, Map<String, String>? v, {bool enabled = true}) {
            final selected = store.voice?['name'] == v?['name'];
            return ListTile(
              enabled: enabled,
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : null,
              selected: selected,
              onTap: () => pick(v),
            );
          }

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text('Voix ${store.course.native}', style: Theme.of(context).textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'Touchez une voix pour l’écouter : certaines rendent mieux les tons que d’autres.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                tile('Par défaut', 'Celle des réglages de synthèse vocale', null),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                for (final (i, v) in voices.indexed)
                  tile(
                    'Voix ${i + 1}',
                    [
                      v['name']!,
                      if (isOnline(v)) 'en ligne',
                      if (isMissing(v)) 'à télécharger dans les réglages de synthèse vocale',
                    ].join(' · '),
                    v,
                    enabled: !isMissing(v),
                  ),
              ],
            ),
          );
        },
      ),
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
