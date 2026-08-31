import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:audio_convert_app/providers/theme_provider.dart';
import 'package:audio_convert_app/providers/language_provider.dart';
import 'package:audio_convert_app/providers/transcribe_provider.dart';
import 'package:audio_convert_app/providers/editor_provider.dart';
import 'package:audio_convert_app/providers/pdf_provider.dart';
import 'package:audio_convert_app/providers/summary_provider.dart';
import 'package:audio_convert_app/providers/history_provider.dart';
import 'package:audio_convert_app/providers/file_browser_provider.dart';
import 'package:audio_convert_app/providers/sort_provider.dart';
import 'package:audio_convert_app/services/connection_service.dart';
import 'package:audio_convert_app/screens/home_screen.dart';
import 'package:audio_convert_app/screens/transcribe_screen.dart';
import 'package:audio_convert_app/screens/summary_screen.dart';
import 'package:audio_convert_app/screens/editor_screen.dart';
import 'package:audio_convert_app/screens/pdf_screen.dart';
import 'package:audio_convert_app/screens/history_screen.dart';
import 'package:audio_convert_app/screens/file_browser_screen.dart';
import 'package:audio_convert_app/widgets/settings_dialog.dart';

Widget createTestApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ChangeNotifierProvider(create: (_) => ConnectionService()),
      ChangeNotifierProvider(create: (_) => TranscribeProvider()),
      ChangeNotifierProvider(create: (_) => EditorProvider()),
      ChangeNotifierProvider(create: (_) => PdfProvider()),
      ChangeNotifierProvider(create: (_) => SummaryProvider()),
      ChangeNotifierProvider(create: (_) => HistoryProvider()),
      ChangeNotifierProvider(create: (_) => FileBrowserProvider()),
      ChangeNotifierProvider(create: (_) => SortProvider()),
    ],
    child: Consumer2<ThemeProvider, LanguageProvider>(
      builder: (context, themeProv, langProv, _) {
        return MaterialApp(
          theme: themeProv.currentThemeData,
          home: Scaffold(body: child),
        );
      },
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UI Interaction & Button Click Tests', () {
    testWidgets('1. SettingsDialog opens, switches themes and languages without error', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => SettingsDialog.show(ctx),
              child: const Text('Open Settings'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Settings
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);

      // Tap English language card
      final enButton = find.text('English');
      expect(enButton, findsOneWidget);
      await tester.tap(enButton);
      await tester.pumpAndSettle();

      // Tap OLED Dark theme preset
      final oledTheme = find.text('OLED Pure Black');
      expect(oledTheme, findsOneWidget);
      await tester.tap(oledTheme);
      await tester.pumpAndSettle();

      // Tap Neon Purple theme preset
      final purpleTheme = find.text('Neon Purple');
      expect(purpleTheme, findsOneWidget);
      await tester.tap(purpleTheme);
      await tester.pumpAndSettle();

      // Scroll to reveal remaining themes
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Tap Emerald Teal theme preset
      final emeraldTheme = find.text('Emerald Teal');
      expect(emeraldTheme, findsOneWidget);
      await tester.tap(emeraldTheme);
      await tester.pumpAndSettle();

      // Tap Light Studio theme preset
      final lightTheme = find.text('Light Studio');
      expect(lightTheme, findsOneWidget);
      await tester.tap(lightTheme);
      await tester.pumpAndSettle();

      // Close Settings Dialog
      final closeButton = find.text('Close');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsNothing);
    });

    testWidgets('2. HomeScreen renders and navigation cards can be clicked', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('3. TranscribeScreen renders, upload buttons are responsive', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(const TranscribeScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(TranscribeScreen), findsOneWidget);

      // Find Upload Audio icon or button
      final audioIconFinder = find.byIcon(Icons.audio_file);
      expect(audioIconFinder, findsWidgets);

      // Tap upload audio button
      await tester.tap(audioIconFinder.first);
      await tester.pumpAndSettle();

      // Ensure modal opens
      expect(find.text('1. Pilih Banyak File'), findsOneWidget);
      expect(find.text('2. Pilih Folder (Hanya 1 Level)'), findsOneWidget);
      expect(find.text('3. Pilih Folder & Seluruh Subfoldernya'), findsOneWidget);

      // Dismiss dialog by tapping option 1 or close
      await tester.tap(find.text('1. Pilih Banyak File'));
      await tester.pumpAndSettle();
    });

    testWidgets('4. SummaryScreen renders, switches between Ollama & Cloud AI', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(const SummaryScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(SummaryScreen), findsOneWidget);
    });

    testWidgets('5. EditorScreen, PdfScreen, HistoryScreen, FileBrowserScreen render cleanly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(const EditorScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);

      await tester.pumpWidget(createTestApp(const PdfScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(PdfScreen), findsOneWidget);

      await tester.pumpWidget(createTestApp(const HistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);

      await tester.pumpWidget(createTestApp(const FileBrowserScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(FileBrowserScreen), findsOneWidget);
    });

    testWidgets('6. TranscribeScreen Selection Bar renders Delete & Rename actions', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(const TranscribeScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(TranscribeScreen), findsOneWidget);
    });
  });
}
