import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/providers.dart';
import 'screens/add_split_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/create_group_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/split_detail_screen.dart';
import 'screens/split_screen.dart';
import 'screens/transaction_details_screen.dart';
import 'screens/web_page_screen.dart';
import 'widgets/app_shell.dart';
import 'widgets/splash_screen.dart';

/// Re-runs the redirect whenever the auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}

/// Same paths as the web app (src/App.jsx). Everything except /login needs a user
/// (web: ProtectedRoute); after sign-in the user returns to where they were headed.
final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    refreshListenable: listenable,
    initialLocation: '/',
    redirect: (context, state) {
      // Legal pages are public, like on the website (the login screen links to them)
      if (state.matchedLocation == '/legal') return null;
      final auth = ref.read(authStateProvider);
      if (auth.isLoading && !auth.hasValue) return '/splash';
      final loggedIn = auth.value != null;
      final loc = state.matchedLocation;
      final atLogin = loc == '/login';

      if (!loggedIn) {
        if (atLogin) return null;
        final from = state.uri.toString();
        return from == '/' || from == '/splash' ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
      }
      if (atLogin || loc == '/splash') {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : '/';
      }
      return null;
    },
    errorBuilder: (context, state) => const AppShell(child: NotFoundScreen()),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(path: '/login', pageBuilder: (_, state) => fadePage(state, const LoginScreen())),
      GoRoute(
        path: '/legal',
        builder: (_, state) => WebPageScreen(
          path: state.uri.queryParameters['path'] ?? '/privacy',
          title: state.uri.queryParameters['title'] ?? 'BudgetMate',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (_, state) => fadePage(state, const DashboardScreen())),
          GoRoute(
            path: '/expenses',
            pageBuilder: (_, state) => fadePage(state, const ExpensesScreen()),
            routes: [
              GoRoute(path: 'add', builder: (_, _) => const AddTransactionScreen()),
              GoRoute(path: ':id', builder: (_, state) => TransactionDetailsScreen(id: state.pathParameters['id']!)),
            ],
          ),
          GoRoute(
            path: '/scan',
            pageBuilder: (_, state) {
              final extra = state.extra;
              return fadePage(state, ScanScreen(
                initialFile: extra is File ? extra : null,
                groupId: extra is Map ? extra['groupId'] as String? : null,
              ));
            },
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (_, state) => fadePage(state, const GroupsScreen()),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const CreateGroupScreen()),
              GoRoute(
                path: ':groupId',
                builder: (_, state) => GroupDetailScreen(groupId: state.pathParameters['groupId']!),
                routes: [
                  GoRoute(
                    path: 'split/new',
                    builder: (_, state) => AddSplitScreen(groupId: state.pathParameters['groupId']!),
                  ),
                  GoRoute(
                    path: 'split/:splitId',
                    builder: (_, state) =>
                        SplitDetailScreen(groupId: state.pathParameters['groupId']!, splitId: state.pathParameters['splitId']!),
                    routes: [
                      GoRoute(
                        path: 'screen',
                        // Reached as split/new/screen with the bill in `extra` (web: location.state)
                        builder: (_, state) =>
                            SplitScreen(groupId: state.pathParameters['groupId']!, data: state.extra as Map<String, dynamic>?),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: '/analytics', pageBuilder: (_, state) => fadePage(state, const AnalyticsScreen())),
          GoRoute(path: '/settings', pageBuilder: (_, state) => fadePage(state, const SettingsScreen())),
        ],
      ),
    ],
  );
});

/// Tab-to-tab transition: the new page fades in while rising slightly (detail pages
/// pushed on top keep the platform's default slide).
CustomTransitionPage<void> fadePage(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
