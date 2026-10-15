import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'coach.dart';
import 'home.dart';
import 'lexicon.dart';
import 'onboarding.dart';
import 'quiz.dart';
import 'review.dart';
import 'settings.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  syncReminder();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (light, dark) {
      dynamicColorAvailable = light != null;
      // Rebuilt only when an appearance setting changes, not on every grade.
      return ValueListenableBuilder(
        valueListenable: store.appearance,
        builder: (context, _, _) {
          // The wallpaper's primary as seed: the full Material 3 scheme (with every
          // surface-container role) in the system's colors.
          ColorScheme scheme(Brightness b, ColorScheme? system) => ColorScheme.fromSeed(
            seedColor: store.dynamicColor && system != null ? system.primary : seeds[store.seed].color,
            brightness: b,
          );
          return MaterialApp(
            title: 'LLLearner',
            scaffoldMessengerKey: messenger,
            navigatorObservers: [_stopSpeech],
            debugShowCheckedModeBanner: false,
            themeMode: store.themeMode,
            theme: buildTheme(scheme(Brightness.light, light)),
            darkTheme: buildTheme(scheme(Brightness.dark, dark)),
            home: ListenableBuilder(
              listenable: store,
              builder: (context, _) => store.onboarded ? const Shell() : const Onboarding(),
            ),
          );
        },
      );
    },
  );
}

/// Leaving a page or a sheet (back, close, next lesson) cuts off the word or sentence being read.
class _StopSpeech extends NavigatorObserver {
  @override
  void didPop(Route route, Route? previousRoute) => tts.stop();

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => tts.stop();
}

final _stopSpeech = _StopSpeech();

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  void go(int i) => setState(() => tab = i);

  @override
  void initState() {
    super.initState();
    // Replies shared from the Claude app: while running, and the one that launched us.
    claude.setMethodCallHandler((call) async => _fromClaude(call.arguments as String));
    claude.invokeMethod<String>('takeSharedText').then((t) => t == null ? null : _fromClaude(t), onError: (_) {});
  }

  void _fromClaude(String text) {
    final msg = importDeck(text);
    Navigator.of(context).popUntil((r) => r.isFirst);
    go(0); // imported words are the next lessons
    messenger.currentState?.showSnackBar(SnackBar(content: Text('Assistant IA → $msg')));
  }

  static const _tabs = [
    (Icons.school_outlined, Icons.school, 'Apprendre'),
    (Icons.style_outlined, Icons.style, 'Réviser'),
    (Icons.quiz_outlined, Icons.quiz, 'Pratiquer'),
    (Icons.menu_book_outlined, Icons.menu_book, 'Lexique'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Assistant'),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final due = store.due.length;
      // Not const: identical const widgets are skipped on rebuild, so they wouldn't show store changes.
      final pages = [LearnTab(), ReviewTab(), PracticeTab(), LexiconTab(), CoachTab()];
      return Scaffold(
        appBar: AppBar(titleSpacing: 12, title: CourseButton(), actions: [StreakChip(), const SizedBox(width: 12)]),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: go,
          destinations: [
            for (final (i, (icon, selected, label)) in _tabs.indexed)
              NavigationDestination(
                icon: Badge(isLabelVisible: i == 1 && due > 0, label: Text('$due'), child: Icon(icon)),
                selectedIcon: Badge(isLabelVisible: i == 1 && due > 0, label: Text('$due'), child: Icon(selected)),
                label: label,
              ),
          ],
        ),
      );
    },
  );
}
