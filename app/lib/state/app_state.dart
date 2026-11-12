import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/feeds.dart';
import '../models/event.dart';
import '../models/job.dart';
import '../services/notifications.dart';
import '../services/watch.dart';

enum TimeFilter {
  all('Alle'),
  today('Heute'),
  weekend('Wochenende'),
  month('Diesen Monat');

  const TimeFilter(this.label);
  final String label;
}

enum LocationStatus { unknown, searching, ok, denied, off }

/// Zeitraum-Filter für Ferienjobs.
enum JobPeriod {
  all('Alle'),
  weihnachten('Weihnachtsferien'),
  ostern('Osterferien'),
  sommer('Sommerferien'),
  herbst('Herbstferien'),
  nebenbei('Nebenbei');

  const JobPeriod(this.label);
  final String label;

  bool matches(String p) => switch (this) {
        JobPeriod.all => true,
        JobPeriod.weihnachten => p == 'Weihnachtsferien' || p == 'Ferien',
        JobPeriod.ostern => p == 'Osterferien' || p == 'Ferien',
        JobPeriod.sommer => p == 'Sommerferien' || p == 'Ferien',
        JobPeriod.herbst => p == 'Herbstferien' || p == 'Ferien',
        JobPeriod.nebenbei => p == 'Nebenbei',
      };
}

/// Bezahlungs-Filter für Ferienjobs.
enum JobPay {
  all('Alle'),
  stated('Mit Lohnangabe'),
  min12('ab 12 €/Std.');

  const JobPay(this.label);
  final String label;
}

class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;
  final _distance = const Distance();

  // ---- Daten -----------------------------------------------------------------------
  final Map<String, FeedData> _feeds = {};
  DateTime? lastFetch;
  String? fetchError;
  bool loading = true;
  bool refreshing = false;

  List<OpenDayEvent> get _events => [
        ...?_feeds['events.json']?.events,
        ...?_feeds['freizeit.json']?.events,
      ];
  List<Job> get _jobs => _feeds['jobs.json']?.jobs ?? const [];
  DateTime? get generated => _feeds.values.map((f) => f.generated).fold<DateTime?>(
      null, (a, b) => a == null || b.isAfter(a) ? b : a);

  // ---- Einstellungen ---------------------------------------------------------------
  late ThemeMode themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
  late int? radiusKm = _prefs.containsKey('radiusKm') ? _prefs.getInt('radiusKm') : null;
  late bool reminders = _prefs.getBool('reminders') ?? true;
  late int age = _prefs.getInt('age') ?? 14;
  late String dataBase = _initialBase();
  late bool calmMap = _prefs.getBool('calmMap') ?? true;
  late final Set<String> favorites = {...?_prefs.getStringList('favorites')};

  /// Kategorien, die ich gar nicht sehen will (Einstellungen).
  late final Set<String> hiddenCategories = {...?_prefs.getStringList('hiddenCategories')};

  // Mitteilungen über neue Einträge
  late bool notifyOffene = _prefs.getBool(NotifyPrefs.offene) ?? false;
  late bool notifyFreizeit = _prefs.getBool(NotifyPrefs.freizeit) ?? false;
  late bool notifyJobs = _prefs.getBool(NotifyPrefs.jobs) ?? true;
  late int notifyRadiusKm = _prefs.getInt(NotifyPrefs.radius) ?? 10;

  String _initialBase() {
    final b = _prefs.getString('dataBase');
    if (b != null && b.isNotEmpty) return b;
    // ältere Version: es gab nur eine Adresse für events.json
    final old = _prefs.getString('sourceUrl');
    if (old != null && old.endsWith('.json')) return old.substring(0, old.lastIndexOf('/') + 1);
    return kDefaultDataBase;
  }

  // ---- Filter (nur für diese Sitzung) ------------------------------------------------
  TimeFilter timeFilter = TimeFilter.all;
  final Set<Area> areas = {...Area.values};
  late final Set<Category> categories = {...Category.values};
  bool onlyFree = false;

  // Ferienjob-Filter
  int? jobRadiusKm = 25;
  final Set<JobType> jobTypes = {};
  JobPeriod jobPeriod = JobPeriod.all;
  JobPay jobPay = JobPay.all;

  // ---- Standort --------------------------------------------------------------------
  LatLng? myLocation;
  LocationStatus locationStatus = LocationStatus.unknown;

  // =================================================================================
  // Laden
  // =================================================================================

  Future<void> init() async {
    final lat = _prefs.getDouble('lastLat'), lng = _prefs.getDouble('lastLng');
    if (lat != null && lng != null) myLocation = LatLng(lat, lng);
    for (final f in FeedStore.files) {
      final d = await FeedStore.loadLocal(f);
      if (d != null) _feeds[f] = d;
    }
    loading = false;
    notifyListeners();
    unawaited(refresh());
    unawaited(_quietLocation());
    unawaited(NewItemsWatcher.schedule(_prefs));
  }

  /// Holt die neuesten Dateien. Bei Fehlern bleibt der gespeicherte Stand.
  Future<void> refresh() async {
    final base = dataBase.trim();
    if (base.isEmpty || refreshing) return;
    refreshing = true;
    notifyListeners();
    String? error;
    var anyOk = false;
    for (final f in FeedStore.files) {
      try {
        final d = await FeedStore.fetch(base, f, newerThan: _feeds[f]?.generated);
        if (d != null) _feeds[f] = d;
        anyOk = true;
      } on TimeoutException {
        error = 'Keine Antwort vom Server – zeige gespeicherte Daten.';
      } on SocketException {
        error = 'Offline – zeige gespeicherte Daten.';
      } catch (e) {
        error = 'Aktualisieren fehlgeschlagen ($e).';
      }
    }
    if (anyOk) lastFetch = DateTime.now();
    fetchError = anyOk ? null : error;
    refreshing = false;
    notifyListeners();
    await rescheduleReminders();
    await NewItemsWatcher.check(_prefs, Map.of(_feeds));
  }

  // =================================================================================
  // Abfragen: Termine & Events
  // =================================================================================

  bool categoryVisible(Category c) => !hiddenCategories.contains(c.id);

  /// Alles, was für mich in Frage kommt: nicht vorbei, Alter passt, im Suchradius, Kategorie erwünscht.
  List<OpenDayEvent> get relevant {
    final now = DateTime.now();
    return _events.where((e) {
      if (e.isPast(now) || !e.allowedFor(age) || !categoryVisible(e.category)) return false;
      final d = distanceKm(e.point);
      if (radiusKm != null && d != null && d > radiusKm!) return false;
      return true;
    }).toList();
  }

  bool _passesSessionFilters(OpenDayEvent e) {
    if (!areas.contains(e.area) || !categories.contains(e.category)) return false;
    if (onlyFree && e.area == Area.freizeit && e.free != true) return false;
    return true;
  }

  /// Für Karte: Bereich, Kategorie, "nur kostenlos" und Zeitfilter.
  List<OpenDayEvent> get mapEvents =>
      relevant.where((e) => _passesSessionFilters(e) && _matchesTime(e)).toList();

  /// Für Kalender: wie Karte, aber alle Zeiten.
  List<OpenDayEvent> get calendarEvents => relevant.where(_passesSessionFilters).toList();

  List<OpenDayEvent> eventsOn(DateTime day) {
    final list = calendarEvents.where((e) => e.occursOn(day)).toList();
    sortByDistance(list);
    return list;
  }

  List<OpenDayEvent> get favoriteEvents {
    final now = DateTime.now();
    return _events.where((e) => favorites.contains(e.id) && !e.isPast(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  int get allCount => _events.length;
  int get hiddenByAge => _events.where((e) => !e.allowedFor(age) && !e.isPast(DateTime.now())).length;
  int countIn(Area a) => _events.where((e) => e.area == a).length;

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
        final sat = wd == DateTime.sunday
            ? today.subtract(const Duration(days: 1))
            : today.add(Duration(days: DateTime.saturday - wd));
        final sun = sat.add(const Duration(days: 1));
        return e.occursOn(sat) || e.occursOn(sun);
      case TimeFilter.month:
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        return e.start.isBefore(monthEnd);
    }
  }

  double? distanceKm(LatLng? p) {
    if (myLocation == null || p == null) return null;
    return _distance.as(LengthUnit.Meter, myLocation!, p) / 1000;
  }

  void sortByDistance(List<OpenDayEvent> list) {
    list.sort((a, b) {
      final da = distanceKm(a.point), db = distanceKm(b.point);
      if (da == null && db == null) return a.start.compareTo(b.start);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
  }

  // =================================================================================
  // Abfragen: Ferienjobs
  // =================================================================================

  List<Job> get allowedJobs => _jobs.where((j) => j.allowedFor(age)).toList();
  int get jobsTooYoung => _jobs.where((j) => !j.allowedFor(age)).length;
  int get jobCount => _jobs.length;

  List<Job> get filteredJobs {
    final list = allowedJobs.where((j) {
      final d = distanceKm(j.point);
      if (jobRadiusKm != null && d != null && d > jobRadiusKm!) return false;
      if (jobTypes.isNotEmpty && !jobTypes.contains(j.type)) return false;
      if (!jobPeriod.matches(j.period)) return false;
      if (jobPay == JobPay.stated && j.pay.isEmpty) return false;
      if (jobPay == JobPay.min12 && (j.payPerHour ?? 0) < 12) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      final da = distanceKm(a.point) ?? 9999, db = distanceKm(b.point) ?? 9999;
      return da.compareTo(db);
    });
    return list;
  }

  List<Job> get favoriteJobs => _jobs.where((j) => favorites.contains(j.id)).toList();

  bool get jobFiltersActive =>
      jobTypes.isNotEmpty || jobPeriod != JobPeriod.all || jobPay != JobPay.all || jobRadiusKm != 25;

  void setJobFilters({int? radius, bool clearRadius = false, JobPeriod? period, JobPay? pay}) {
    if (clearRadius) {
      jobRadiusKm = null;
    } else if (radius != null) {
      jobRadiusKm = radius;
    }
    if (period != null) jobPeriod = period;
    if (pay != null) jobPay = pay;
    notifyListeners();
  }

  void toggleJobType(JobType t) {
    jobTypes.contains(t) ? jobTypes.remove(t) : jobTypes.add(t);
    notifyListeners();
  }

  void resetJobFilters() {
    jobRadiusKm = 25;
    jobTypes.clear();
    jobPeriod = JobPeriod.all;
    jobPay = JobPay.all;
    notifyListeners();
  }

  // =================================================================================
  // Aktionen: Filter
  // =================================================================================

  void setTimeFilter(TimeFilter f) {
    timeFilter = f;
    notifyListeners();
  }

  void toggleArea(Area a) {
    if (areas.contains(a)) {
      if (areas.length > 1) areas.remove(a); // mindestens ein Bereich bleibt an
    } else {
      areas.add(a);
    }
    notifyListeners();
  }

  void toggleCategory(Category c) {
    final inArea = c.area.categories;
    final activeInArea = inArea.where(categories.contains).toList();
    if (categories.contains(c)) {
      if (activeInArea.length == 1) {
        categories.addAll(inArea); // letzte im Bereich abgewählt -> wieder alle des Bereichs
      } else {
        categories.remove(c);
      }
    } else {
      categories.add(c);
    }
    notifyListeners();
  }

  /// Nur diese Kategorie im eigenen Bereich zeigen (andere Bereiche bleiben, wie sie sind).
  void onlyCategory(Category c) {
    categories.removeAll(c.area.categories);
    categories.add(c);
    notifyListeners();
  }

  void setOnlyFree(bool v) {
    onlyFree = v;
    notifyListeners();
  }

  void resetFilters() {
    timeFilter = TimeFilter.all;
    areas.addAll(Area.values);
    categories.addAll(Category.values);
    onlyFree = false;
    notifyListeners();
  }

  bool get filtersActive =>
      timeFilter != TimeFilter.all || areas.length < Area.values.length ||
      categories.length < Category.values.length || onlyFree;

  // =================================================================================
  // Aktionen: Favoriten & Erinnerungen
  // =================================================================================

  bool isFavoriteId(String id) => favorites.contains(id);
  bool isFavorite(OpenDayEvent e) => favorites.contains(e.id);

  /// Gibt true zurück, wenn der Eintrag jetzt gemerkt ist.
  Future<bool> toggleFavoriteId(String id, {bool remind = true}) async {
    final added = !favorites.remove(id);
    if (added) favorites.add(id);
    await _prefs.setStringList('favorites', favorites.toList());
    notifyListeners();
    if (added && reminders && remind) {
      await Reminders.instance.requestPermission();
    }
    await rescheduleReminders();
    return added;
  }

  Future<bool> toggleFavorite(OpenDayEvent e) => toggleFavoriteId(e.id);

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

  // =================================================================================
  // Aktionen: Einstellungen
  // =================================================================================

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
    age = a.clamp(10, 99);
    await _prefs.setInt('age', age);
    notifyListeners();
  }

  Future<void> setCalmMap(bool v) async {
    calmMap = v;
    await _prefs.setBool('calmMap', v);
    notifyListeners();
  }

  Future<void> setCategoryVisible(Category c, bool visible) async {
    visible ? hiddenCategories.remove(c.id) : hiddenCategories.add(c.id);
    await _prefs.setStringList('hiddenCategories', hiddenCategories.toList());
    notifyListeners();
  }

  Future<void> setAreaVisible(Area a, bool visible) async {
    for (final c in a.categories) {
      visible ? hiddenCategories.remove(c.id) : hiddenCategories.add(c.id);
    }
    await _prefs.setStringList('hiddenCategories', hiddenCategories.toList());
    notifyListeners();
  }

  Future<void> setNotify({bool? offene, bool? freizeit, bool? jobs, int? radius}) async {
    if (offene != null) await _prefs.setBool(NotifyPrefs.offene, notifyOffene = offene);
    if (freizeit != null) await _prefs.setBool(NotifyPrefs.freizeit, notifyFreizeit = freizeit);
    if (jobs != null) await _prefs.setBool(NotifyPrefs.jobs, notifyJobs = jobs);
    if (radius != null) await _prefs.setInt(NotifyPrefs.radius, notifyRadiusKm = radius);
    notifyListeners();
    if (offene == true || freizeit == true || jobs == true) {
      await Reminders.instance.requestPermission();
      if (myLocation == null) await locate();
    }
    await NewItemsWatcher.schedule(_prefs);
  }

  Future<void> setDataBase(String url) async {
    var u = url.trim();
    if (u.endsWith('.json')) u = u.substring(0, u.lastIndexOf('/') + 1);
    dataBase = u;
    await _prefs.setString('dataBase', dataBase);
    notifyListeners();
    await refresh();
  }

  // =================================================================================
  // Standort
  // =================================================================================

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

/// Macht den AppState überall per `AppScope.of(context)` erreichbar.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
