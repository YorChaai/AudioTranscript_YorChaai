import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/transcribe_provider.dart';
import 'providers/editor_provider.dart';
import 'providers/pdf_provider.dart';
import 'providers/summary_provider.dart';
import 'providers/history_provider.dart';
import 'providers/file_browser_provider.dart';
import 'providers/sort_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/language_provider.dart';
import 'services/connection_service.dart';
import 'screens/server_offline_screen.dart';
import 'config/api_config.dart';
import 'config/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // default: localhost untuk desktop, bisa diganti di settings
  if (ApiConfig.isDesktop) {
    ApiConfig.setServer('localhost');
  }

  runApp(const AudioConvertApp());
}

class AudioConvertApp extends StatelessWidget {
  const AudioConvertApp({super.key});

  @override
  Widget build(BuildContext context) {
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
          return MaterialApp.router(
            title: langProv.tr('app_title'),
            debugShowCheckedModeBanner: false,
            theme: themeProv.currentThemeData,
            routerConfig: appRouter,
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              scrollbars: false,
            ),
            builder: (context, child) {
              return Consumer<ConnectionService>(
                builder: (context, conn, _) {
                  // Jika koneksi gagal, tampilkan ServerOfflineScreen dengan Navigator
                  if (!conn.isConnected && !conn.isChecking) {
                    return Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (context) => const ServerOfflineScreen(),
                      ),
                    );
                  }
                  // Optional: Saat awal buka aplikasi (sedang cek pertama kali)
                  if (conn.isChecking && !conn.isConnected && conn.serverTime == null) {
                    return Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (context) => Scaffold(
                          backgroundColor: themeProv.currentPreset.background,
                          body: Center(
                            child: CircularProgressIndicator(color: themeProv.currentPreset.primary),
                          ),
                        ),
                      ),
                    );
                  }
                  return child ?? const SizedBox.shrink();
                },
              );
            },
          );
        },
      ),
    );
  }
}
