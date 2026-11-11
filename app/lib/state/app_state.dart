import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../services/notifications.dart';

/// Adresse der events.json. Wird beim Bauen gesetzt:
///   `flutter build apk --dart-define=EVENTS_URL=https://raw.githubusercontent.com/NAME/offene-tueren/main/data/events.json`
/// und lässt sich in der App unter „Einstellungen → Datenquelle“ ändern.
const kDefaultEventsUrl = String.fromEnvironment('EVENTS_URL');

enum TimeFilter {
  all('Alle'),
  today('Heute'),
  weekend('Wochenende'),
  month('Diesen Monat');

  const TimeFilter(this.label);
  final String label;
}

enum LocationStatus { unknown, searching, ok, denied, off }

class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;
  final _distance = const Distance();

  // ---- Daten -----------------------------------------------------------------------
  List<OpenDayEvent> _events = const [];
  DateTime? generated;
  DateTime? lastFetch;
  String? fetchError;
  bool loading = true;
  bool refreshing = false;

  // ---- Einstellungen ---------------------------------------------------------------
  late ThemeMode themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
  late int? radiusKm = _prefs.containsKey('radiusKm') ? _prefs.getInt('radiusKm') : null;
  late bool reminders = _prefs.getBool('reminders') ?? true;
  late int age = _prefs.getInt('age') ?? 14;
  late String sourceUrl = _prefs.getString('sourceUrl') ?? kDefaultEventsUrl;
  late bool calmMap = _prefs.getBool('calmMap') ?? true;
  late final Set<String> favorites = {...?_prefs.getStringList('favorites')};

  // ---- Filter (nur für diese Sitzung) ------------------------------------------------
  TimeFilter timeFilter = TimeFilter.all;
  final Set<Category> categories = {...Category.values};

  // ---- Standort --------------------------------------------------------------------
  LatLng? myLocation;
  LocationStatus locationStatus = LocationStatus.unknown;

  // =================================================================================
  // Laden
  // =================================================================================

  Future<void> init() async {
    final lat = _prefs.getDouble('lastLat'), lng = _prefs.getDouble('lastLng');
    if (lat != null && lng != null) myLocation = LatLng(lat, lng);

    final cached = await _readCache();
    final bundled = await _readBundled();
    final pick = _newer(cached, bundled);
    if (pick != null) _apply(pick);
    loading = false;
    notifyListeners();

    unawaited(refresh());
    unawaited(_quietLocation());
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/events_cache.json');
  }

  Future<_Feed?> _readCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      return _Feed.parse(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<_Feed?> _readBundled() async {
    try {
      return _Feed.parse(await rootBundle.loadString('assets/events.json'));
    } catch (_) {
      return null;
    }
  }

  _Feed? _newer(_Feed? a, _Feed? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.generated.isAfter(a.generated) ? b : a;
  }

  void _apply(_Feed feed) {
    _events = feed.events;
    generated = feed.generated;
  }

  /// Holt die neueste events.json. Bei Fehlern bleibt der gespeicherte Stand.
  Future<void> refresh() async {
    final url = sourceUrl.trim();
    if (url.isEmpty || refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = utf8.decode(res.bodyBytes);
      final feed = _Feed.parse(body);
      if (feed == null) throw const FormatException('Datei hat ein unbekanntes Format');
      if (generated == null || !feed.generated.isBefore(generated!)) {
        _apply(feed);
        await (await _cacheFile()).writeAsString(body, flush: true);
      }
      lastFetch = DateTime.now();
      fetchError = null;
      await rescheduleReminders();
    } on TimeoutException {
      fetchError = 'Keine Antwort vom Server – zeige gespeicherte Termine.';
    } on SocketException {
      fetchError = 'Offline – zeige gespeicherte Termine.';
    } catch (e) {
      fetchError = 'Aktualisieren fehlgeschlagen ($e).';
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  // =================================================================================
  // Abfragen
  // =================================================================================

  /// Alles, was für mich in Frage kommt: nicht vorbei, Alter passt, im Suchradius.
  List<OpenDayEvent> get relevant {
    final now = DateTime.now();
    return _events.where((e) {
      if (e.isPast(now) || !e.allowedFor(age)) return false;
      final d = distanceKm(e);
      if (radiusKm != null && d != null && d > radiusKm!) return false;
      return true;
    }).toList();
  }

  /// Für Karte: zusätzlich Zeit- und Kategorienfilter.
  List<OpenDayEvent> get mapEvents =>
      relevant.where((e) => categories.contains(e.category) && _matchesTime(e)).toList();

  /// Für Kalender: Kategorienfilter, aber alle Zeiten.
  List<OpenDayEvent> get calendarEvents =>
      relevant.where((e) => categories.contains(e.category)).toList();

  List<OpenDayEvent> eventsOn(DateTime day) {
    final list = calendarEvents.where((e) => e.occursOn(day)).toList();
    sortByDistance(list);
    return list;
  }

  List<OpenDayEvent> get favoriteEvents {
    final now = DateTime.now();
    final list = _events.where((e) => favorites.contains(e.id) && !e.isPast(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  int get allCount => _events.length;
  int get hiddenByAge => _events.where((e) => !e.allowedFor(age) && !e.isPast(DateTime.now())).length;

  bool _matchesTime(OpenDayEvent e) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (timeFilter) {
      case TimeFilter.all:
        return true;
      case TimeFilter.today:
        return e.occursOn(today);
      case TimeFilter.weekend:
        // kommender (oder laufender) Samstag + Sonntag
        final wd = today.weekday; // 1 = Montag … 7 = Sonntag
        final sat = wd == DateTime.sunday ? today.subtract(const Duration(days: 1)) : today.add(Duration(days: DateTime.saturday - wd));
        final sun = sat.add(const Duration(days: 1));
        return e.occursOn(sat) || e.occursOn(sun);
      case TimeFilter.month:
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        return e.start.isBefore(monthEnd);
    }
  }

  double? distanceKm(OpenDayEvent e) {
    if (myLocation == null || e.point == null) return null;
    return _distance.as(LengthUnit.Meter, myLocation!, e.point!) / 1000;
  }

  void sortByDistance(List<OpenDayEvent> list) {
    list.sort((a, b) {
      final da = distanceKm(a), db = distanceKm(b);
      if (da == null && db == null) return a.start.compareTo(b.start);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
  }

  // =================================================================================
  // Aktionen
  // =================================================================================

  void setTimeFilter(TimeFilter f) {
    timeFilter = f;
    notifyListeners();
  }

  void toggleCategory(Category c) {
    if (categories.contains(c)) {
      if (categories.length == 1) {
        categories.addAll(Category.values); // letzte abgewählt -> wieder alle
      } else {
        categories.remove(c);
      }
    } else {
      categories.add(c);
    }
    notifyListeners();
  }

  void onlyCategory(Category c) {
    categories
      ..clear()
      ..add(c);
    notifyListeners();
  }

  bool isFavorite(OpenDayEvent e) => favorites.contains(e.id);

  /// Gibt true zurück, wenn der Termin jetzt gemerkt ist.
  Future<bool> toggleFavorite(OpenDayEvent e) async {
    final added = !favorites.remove(e.id);
    if (added) favorites.add(e.id);
    await _prefs.setStringList('favorites', favorites.toList());
    notifyListeners();
    if (added && reminders) {
      await Reminders.instance.requestPermission();
    }
    await rescheduleReminders();
    return added;
  }

  Future<void> setReminders(bool on) async {
    reminders = on;
    await _prefs.setBool('reminders', on);
    notifyListeners();
    if (on) await Reminders.instance.requestPermission();
    await rescheduleReminders();
  }

  Future<void> rescheduleReminders() async {
    await Reminders.instance.sync(reminders ? favoriteEvents : const []);
  }

  Future<void> setRadius(int? km) async {
    radiusKm = km;
    if (km == null) {
      await _prefs.remove('radiusKm');
    } else {
      await _prefs.setInt('radiusKm', km);
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  Future<void> setAge(int a) async {
    age = a.clamp(8, 99);
    await _prefs.setInt('age', age);
    notifyListeners();
  }

  Future<void> setCalmMap(bool v) async {
    calmMap = v;
    await _prefs.setBool('calmMap', v);
    notifyListeners();
  }

  Future<void> setSourceUrl(String url) async {
    sourceUrl = url.trim();
    await _prefs.setString('sourceUrl', sourceUrl);
    notifyListeners();
    await refresh();
  }

  /// Standort ohne Nachfrage holen, wenn die Erlaubnis schon da ist.
  Future<void> _quietLocation() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
      await locate(ask: false);
    }
  }

  /// Fragt bei Bedarf nach der Standort-Erlaubnis. Gibt den Standort zurück (oder null).
  Future<LatLng?> locate({bool ask = true}) async {
    locationStatus = LocationStatus.searching;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationStatus = LocationStatus.off;
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        locationStatus = LocationStatus.denied;
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _setLocation(LatLng(last.latitude, last.longitude));
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _setLocation(LatLng(pos.latitude, pos.longitude));
      locationStatus = LocationStatus.ok;
      return myLocation;
    } catch (_) {
      locationStatus = myLocation != null ? LocationStatus.ok : LocationStatus.unknown;
      return myLocation;
    } finally {
      notifyListeners();
    }
  }

  void _setLocation(LatLng p) {
    myLocation = p;
    _prefs.setDouble('lastLat', p.latitude);
    _prefs.setDouble('lastLng', p.longitude);
  }
}

class _Feed {
  _Feed(this.generated, this.events);
  final DateTime generated;
  final List<OpenDayEvent> events;

  static _Feed? parse(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['version'] != 1 || j['events'] is! List) return null;
      final events = <OpenDayEvent>[];
      for (final raw in j['events'] as List) {
        if (raw is Map<String, dynamic>) {
          final e = OpenDayEvent.tryParse(raw);
          if (e != null) events.add(e);
        }
      }
      return _Feed(DateTime.parse(j['generated'] as String), events);
    } catch (_) {
      return null;
    }
  }
}

/// Macht den AppState überall per `AppScope.of(context)` erreichbar.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
