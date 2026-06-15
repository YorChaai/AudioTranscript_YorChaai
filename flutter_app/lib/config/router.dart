import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/app_shell.dart';
import '../screens/home_screen.dart';
import '../screens/transcribe_screen.dart';
import '../screens/editor_screen.dart';
import '../screens/pdf_screen.dart';
import '../screens/history_screen.dart';
import '../screens/summary_screen.dart';
import '../screens/file_browser_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(child: HomeScreen()),
        ),
        GoRoute(
          path: '/transcribe',
          pageBuilder: (context, state) => const NoTransitionPage(child: TranscribeScreen()),
        ),
        GoRoute(
          path: '/editor',
          pageBuilder: (context, state) {
            final file = state.uri.queryParameters['file'];
            return NoTransitionPage(child: EditorScreen(initialFilePath: file));
          },
        ),
        GoRoute(
          path: '/pdf',
          pageBuilder: (context, state) => const NoTransitionPage(child: PdfScreen()),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => const NoTransitionPage(child: HistoryScreen()),
        ),
        GoRoute(
          path: '/summary',
          pageBuilder: (context, state) {
            final file = state.uri.queryParameters['file'];
            return NoTransitionPage(child: SummaryScreen(initialFilePath: file));
          },
        ),
        GoRoute(
          path: '/browser',
          pageBuilder: (context, state) => const NoTransitionPage(child: FileBrowserScreen()),
        ),
      ],
    ),
  ],
);
