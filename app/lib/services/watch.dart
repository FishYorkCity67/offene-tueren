import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../data/feeds.dart';
import '../models/event.dart';
import 'notifications.dart';

/// Einstellungen für "Neue Einträge"-Mitteilungen (gespeichert in SharedPreferences).
class NotifyPrefs {
  static const offene = 'notify_offene';
  static const freizeit = 'notify_freizeit';
  static const jobs = 'notify_jobs';
  static const radius = 'notifyRadiusKm';

  static String keyFor(String file) => switch (file) {
        'events.json' => offene,
        'freizeit.json' => freizeit,
        _ => jobs,
      };

  static bool anyOn(SharedPreferences p) =>
      (p.getBool(offene) ?? false) || (p.getBool(freizeit) ?? false) || (p.getBool(jobs) ?? true);
}

/// Merkt sich, welche Einträge schon bekannt sind, und meldet neue in der Nähe.
class NewItemsWatcher {
  static const _distance = Distance();

  static Future<void> check(SharedPreferences prefs, Map<String, FeedData> feeds) async {
    final age = prefs.getInt('age') ?? 14;
    final radius = prefs.getInt(NotifyPrefs.radius) ?? 10;
    final lat = prefs.getDouble('lastLat'), lng = prefs.getDouble('lastLng');
    final me = lat != null && lng != null ? LatLng(lat, lng) : null;
    final hidden = {...?prefs.getStringList('hiddenCategories')};

    bool near(LatLng? p) {
      if (me == null) return false; // ohne Standort keine "in deiner Nähe"-Mitteilung
      if (p == null) return false;
      return _distance.as(LengthUnit.Kilometer, me, p) <= radius;
    }

    for (final entry in feeds.entries) {
      final file = entry.key;
      final data = entry.value;
      final seenKey = 'seen_$file';
      final seen = prefs.getStringList(seenKey);
      final ids = data.ids.toList();
      await prefs.setStringList(seenKey, ids);
      if (seen == null) continue; // erster Lauf: alles gilt als bekannt
      final on = prefs.getBool(NotifyPrefs.keyFor(file)) ?? (file == 'jobs.json');
      if (!on) continue;
      final old = seen.toSet();
      final now = DateTime.now();

      if (file == 'jobs.json') {
        final fresh = data.jobs.where((j) => !old.contains(j.id) && j.allowedFor(age) && near(j.point)).toList();
        if (fresh.isEmpty) continue;
        await Reminders.instance.showNow(
          id: 9003,
          title: fresh.length == 1 ? 'Neuer Ferienjob in deiner Nähe' : '${fresh.length} neue Ferienjobs in $radius km Umkreis',
          body: fresh.take(3).map((j) => '${j.title} (${j.city})').join(' · '),
        );
      } else {
        final fresh = data.events
            .where((e) => !old.contains(e.id) && !e.isPast(now) && e.allowedFor(age) &&
                !hidden.contains(e.category.id) && near(e.point))
            .toList();
        if (fresh.isEmpty) continue;
        final area = fresh.first.area;
        await Reminders.instance.showNow(
          id: area == Area.freizeit ? 9002 : 9001,
          title: fresh.length == 1
              ? 'Neu in deiner Nähe: ${area.label}'
              : '${fresh.length} neue Termine „${area.label}“ in $radius km Umkreis',
          body: fresh.take(3).map((e) => e.headline).join(' · '),
        );
      }
    }
  }

  /// Hintergrund-Prüfung ein- oder ausschalten (je nachdem, ob eine Mitteilungsart an ist).
  static Future<void> schedule(SharedPreferences prefs) async {
    try {
      if (NotifyPrefs.anyOn(prefs)) {
        await Workmanager().registerPeriodicTask(
          'neue-eintraege',
          'neue-eintraege',
          frequency: const Duration(hours: 6),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await Workmanager().cancelByUniqueName('neue-eintraege');
      }
    } catch (_) {
      // Hintergrund-Prüfung ist ein Extra – die App funktioniert auch ohne.
    }
  }
}

/// Läuft im Hintergrund (Android WorkManager), auch wenn die App geschlossen ist.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final prefs = await SharedPreferences.getInstance();
      await Reminders.instance.init();
      final base = prefs.getString('dataBase') ?? kDefaultDataBase;
      final feeds = <String, FeedData>{};
      for (final f in FeedStore.files) {
        FeedData? d;
        try {
          d = await FeedStore.fetch(base, f);
        } catch (_) {}
        d ??= await FeedStore.loadLocal(f);
        if (d != null) feeds[f] = d;
      }
      await NewItemsWatcher.check(prefs, feeds);
    } catch (_) {}
    return true;
  });
}
