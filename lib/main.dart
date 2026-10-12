import 'package:flutter/material.dart';

import 'coach.dart';
import 'home.dart';
import 'lexicon.dart';
import 'quiz.dart';
import 'review.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  tts.setSpeechRate(0.42);
  runApp(const App());
}

ThemeData _theme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFFB7312C), brightness: b); // vermilion
  return ThemeData(
    colorScheme: cs,
    fontFamilyFallback: const ['RareHan'], // only has the rare glyphs; common ones come from the system font
    scaffoldBackgroundColor: cs.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LLLearner',
    scaffoldMessengerKey: messenger,
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const Shell(),
  );
}

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
    go(3); // Lexique: imported words are listed first
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Claude → $msg'), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final due = store.due.length;
      final pages = [
        HomeScreen(go: go),
        ReviewScreen(go: go),
        QuizScreen(go: go),
        const LexiconScreen(),
        const CoachScreen(),
      ];
      return Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: go,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Badge(isLabelVisible: due > 0, label: Text('$due'), child: const Icon(Icons.style_outlined)),
              selectedIcon: const Icon(Icons.style),
              label: 'Réviser',
            ),
            const NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Quiz'),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Lexique',
            ),
            const NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'Claude',
            ),
          ],
        ),
      );
    },
  );
}
