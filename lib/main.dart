import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'repositories/club_repository.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  if (apiBaseUrl.isEmpty || publishableKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Не задан адрес API. Запустите проект с параметрами из README.',
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final api = ApiClient(apiBaseUrl, publishableKey, prefs);
  final auth = AuthState(api);
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        Provider<ClubRepository>(create: (_) => SupabaseClubRepository(api)),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: const PulseApp(),
    ),
  );
  await auth.init();
}
