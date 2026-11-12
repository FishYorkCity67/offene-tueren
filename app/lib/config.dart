import 'package:flutter/services.dart';

/// Zentrale Einstellungen der App.
///
/// APP-NAME ÄNDERN: nur die Datei `app/assets/app_name.txt` bearbeiten und die APK neu bauen.
/// Daraus lesen sowohl Android (Name unter dem App-Symbol, siehe android/app/build.gradle.kts)
/// als auch die App selbst (Überschriften) den Namen.
class AppConfig {
  static String appName = 'Was geht?';

  static Future<void> load() async {
    try {
      final n = (await rootBundle.loadString('assets/app_name.txt')).trim();
      if (n.isNotEmpty) appName = n;
    } catch (_) {}
  }
}

/// Ordner mit den Daten (events.json, freizeit.json, jobs.json). Beim Bauen änderbar:
///   `flutter build apk --dart-define=DATA_BASE_URL=https://…/data/`
const kDefaultDataBase = String.fromEnvironment(
  'DATA_BASE_URL',
  defaultValue: 'https://raw.githubusercontent.com/FishYorkCity67/offene-tueren/main/data/',
);

/// Offizielle Infos des Bundesarbeitsministeriums zum Kinder- und Jugendarbeitsschutz.
const kBmasJugendarbeitsschutzUrl =
    'https://www.bmas.de/DE/Service/Publikationen/Broschueren/a707-klare-sache-kinder-und-jugendarbeitsschutz.html';
