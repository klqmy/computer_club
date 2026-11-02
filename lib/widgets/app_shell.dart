import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/catalog.dart';
import '../state/auth_state.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    Future<void> logout() async {
      await auth.logout();
      if (context.mounted) context.go('/login');
    }

    final mobile = MediaQuery.sizeOf(context).width < 900;
    final route = GoRouterState.of(context).uri.path;
    final destinations = <({String path, String label, IconData icon})>[
      if (auth.role == 'admin') ...[
        (
          path: '/admin/reports',
          label: 'Обзор клуба',
          icon: Icons.space_dashboard_outlined,
        ),
        (
          path: '/admin/users',
          label: 'Пользователи и роли',
          icon: Icons.admin_panel_settings_outlined,
        ),
      ],
      if (auth.role == 'operator')
        (path: '/shift', label: 'Рабочая смена', icon: Icons.schedule),
      if (auth.role == 'client') ...[
        (
          path: '/catalog',
          label: 'Выбрать компьютер',
          icon: Icons.computer_outlined,
        ),
        (
          path: '/my/bookings',
          label: 'Мои бронирования',
          icon: Icons.event_outlined,
        ),
        (path: '/my/card', label: 'Клубная карта', icon: Icons.badge_outlined),
      ],
      if (auth.role != 'client')
        for (final spec in entities.values)
          (
            path: '/manage/${spec.key}',
            label: spec.title,
            icon: switch (spec.key) {
              'stations' => Icons.computer,
              'games' => Icons.sports_esports_outlined,
              'customers' => Icons.people_outline,
              'bookings' => Icons.event,
              'payments' => Icons.receipt_long,
              _ => Icons.grid_view_outlined,
            },
          ),
    ];
    Widget navigation() => SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 16, 4),
            child: Row(
              children: [
                Icon(Icons.bolt, size: 32, color: Color(0xffc5f36b)),
                SizedBox(width: 8),
                Text(
                  'ПУЛЬС',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 16, 24),
            child: Text(
              'КОМПЬЮТЕРНЫЙ КЛУБ',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.8,
                color: Color(0xff99a3b3),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in destinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: route == d.path,
                      selectedTileColor: const Color(0xff29382a),
                      selectedColor: const Color(0xffc5f36b),
                      leading: Icon(d.icon, size: 20),
                      title: Text(
                        d.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () {
                        if (mobile) Navigator.pop(context);
                        context.go(d.path);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Учебный проект · 2026',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      drawer: mobile ? Drawer(child: navigation()) : null,
      appBar: mobile
          ? AppBar(
              title: const Text('ПУЛЬС'),
              actions: [
                IconButton(
                  tooltip: 'Выйти',
                  onPressed: logout,
                  icon: const Icon(Icons.logout),
                ),
              ],
            )
          : null,
      body: Row(
        children: [
          if (!mobile)
            Container(
              width: 244,
              color: const Color(0xff121925),
              child: navigation(),
            ),
          Expanded(
            child: Column(
              children: [
                if (!mobile)
                  Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xff263141)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 8,
                          color: Color(0xffc5f36b),
                        ),
                        const SizedBox(width: 8),
                        const Text('Клуб онлайн'),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            '${auth.profile?['full_name']} · ${roles[auth.role]}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Выйти',
                          onPressed: logout,
                          icon: const Icon(Icons.logout),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
