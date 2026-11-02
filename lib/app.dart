import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/access.dart';
import 'models/catalog.dart';
import 'screens/auth_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/entity_screen.dart';
import 'screens/home_screens.dart';
import 'state/auth_state.dart';
import 'widgets/app_shell.dart';

class PulseApp extends StatefulWidget {
  const PulseApp({super.key});
  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> {
  GoRouter? router;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthState>();
    router ??= GoRouter(
      refreshListenable: auth,
      initialLocation: '/',
      redirect: (context, state) {
        if (auth.loading) {
          return state.uri.path == '/loading'
              ? null
              : '/loading?next=${Uri.encodeComponent(state.uri.toString())}';
        }
        if (!auth.signedIn) {
          return state.uri.path == '/login'
              ? null
              : '/login?next=${Uri.encodeComponent(state.uri.queryParameters['next'] ?? state.uri.toString())}';
        }
        if (['/', '/login', '/loading'].contains(state.uri.path)) {
          final next = state.uri.queryParameters['next'];
          if (next != null &&
              next.startsWith('/') &&
              !next.startsWith('//') &&
              !['/login', '/loading', '/'].contains(Uri.parse(next).path)) {
            return routeAllowed(auth.role, Uri.parse(next).path)
                ? next
                : '/forbidden';
          }
          return auth.home;
        }
        return routeAllowed(auth.role, state.uri.path) ? null : '/forbidden';
      },
      errorBuilder: (context, state) =>
          const Scaffold(body: Center(child: Text('Страница не найдена'))),
      routes: [
        GoRoute(
          path: '/loading',
          builder: (_, __) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        ShellRoute(
          builder: (_, __, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/admin/reports',
              builder: (_, __) => const OverviewScreen(),
            ),
            GoRoute(
              path: '/admin/users',
              builder: (_, __) => const UsersScreen(),
            ),
            GoRoute(
              path: '/shift',
              builder: (_, __) => const OverviewScreen(operatorView: true),
            ),
            GoRoute(
              path: '/catalog',
              builder: (_, s) => CatalogScreen(uri: s.uri),
            ),
            GoRoute(
              path: '/my/card',
              builder: (_, __) => const MembershipScreen(),
            ),
            GoRoute(
              path: '/my/bookings',
              builder: (_, s) => EntityScreen(
                key: const ValueKey('my-bookings'),
                spec: entities['bookings']!,
                uri: s.uri,
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, s) => EntityScreen(
                    key: ValueKey(s.uri.path),
                    spec: entities['bookings']!,
                    uri: s.uri,
                    id: int.tryParse(s.pathParameters['id']!) ?? -1,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/manage/:entity',
              builder: (_, s) => EntityScreen(
                key: ValueKey(s.pathParameters['entity']),
                spec: entities[s.pathParameters['entity']]!,
                uri: s.uri,
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, s) => EntityScreen(
                    key: ValueKey(s.uri.path),
                    spec: entities[s.pathParameters['entity']]!,
                    uri: s.uri,
                    id: int.tryParse(s.pathParameters['id']!) ?? -1,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/forbidden',
              builder: (context, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 56,
                        color: Color(0xffc5f36b),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Этот раздел недоступен вашей роли',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => context.go(auth.home),
                        child: const Text('На главную'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'ПУЛЬС · компьютерный клуб',
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff0d131d),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc5f36b),
        brightness: Brightness.dark,
        primary: const Color(0xffc5f36b),
        onPrimary: const Color(0xff17230f),
        surface: const Color(0xff17212e),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xff17212e),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xff263344)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff141e2b),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    ),
  );
}
