import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workmanager/workmanager.dart';

import 'config.dart';
import 'services/notifications.dart';
import 'services/watch.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  Intl.defaultLocale = 'de_DE';
  await initializeDateFormatting('de_DE');
  await AppConfig.load();
  final prefs = await SharedPreferences.getInstance();
  try {
    await Reminders.instance.init();
  } catch (_) {
    // Ohne Mitteilungen läuft die App trotzdem.
  }
  try {
    await Workmanager().initialize(backgroundDispatcher);
  } catch (_) {
    // Hintergrund-Prüfung ist ein Extra.
  }
  final state = AppState(prefs);
  await state.init();
  runApp(OffeneTuerenApp(state: state));
}

class OffeneTuerenApp extends StatelessWidget {
  const OffeneTuerenApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Palette.light),
          darkTheme: buildTheme(Palette.night),
          themeMode: state.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          locale: const Locale('de', 'DE'),
          supportedLocales: const [Locale('de', 'DE')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
