import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lllearner/store.dart';
import 'package:lllearner/theme.dart';
import 'package:lllearner/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a word tapped in an example opens below it, characters taken apart in place', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lllearner');
    addTearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => store.load(dir: dir.path));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(ColorScheme.fromSeed(seedColor: seeds.first.color)),
        home: Scaffold(
          body: ListView(
            children: const [ExampleTile((hanzi: '我好飽。', roman: 'Wǒ hǎo bǎo.', fr: 'Je suis repu.'), highlight: '飽')],
          ),
        ),
      ),
    );
    expect(find.textContaining('Idéophonogramme'), findsNothing);

    await tester.tap(find.text('飽'));
    await tester.pumpAndSettle();
    expect(find.text(store.byKey('man:飽')!.fr), findsOneWidget); // the word, under the sentence
    expect(find.textContaining('Idéophonogramme'), findsOneWidget); // one character: shown at once

    await tester.tap(find.textContaining('· son')); // 包, the sound part
    await tester.pumpAndSettle();
    expect(find.textContaining('Idéogramme composé'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget); // 飽 › 包

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.textContaining('Idéogramme'), findsNothing);
  });
}
