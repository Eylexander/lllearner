import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lllearner/main.dart';
import 'package:lllearner/store.dart';
import 'package:lllearner/theme.dart';
import 'package:lllearner/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the tabs and the app bar follow store changes', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lllearner');
    addTearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => store.load(dir: dir.path));
    store.onboarded = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(ColorScheme.fromSeed(seedColor: seeds.first.color)),
        home: const Shell(),
      ),
    );
    expect(find.textContaining('Commencer'), findsOneWidget);
    expect(find.descendant(of: find.byType(StreakChip), matching: find.text('0')), findsOneWidget);

    for (final w in store.nextLesson!.words) {
      store.learn(w);
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Continuer'), findsOneWidget);
    expect(find.descendant(of: find.byType(StreakChip), matching: find.text('1')), findsOneWidget);
  });
}
