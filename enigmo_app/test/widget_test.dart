// This is a basic Flutter widget test for Enigmo app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enigmo_app/main.dart';

void main() {
  testWidgets('AnogramApp widget test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AnogramApp());

    // Verify that the app loads without errors
    expect(find.byType(MaterialApp), findsOneWidget);
    
    // Verify that the ChatListScreen is displayed with the new title
    expect(find.text('Enigmo'), findsOneWidget);
    
    // Pump a few frames to let the UI settle, but don't wait for network
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('MaterialApp configuration test', (WidgetTester tester) async {
    await tester.pumpWidget(const AnogramApp());
    
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    
    expect(materialApp.title, equals('Enigmo'));
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
    expect(materialApp.theme, isNotNull);
  });
}
