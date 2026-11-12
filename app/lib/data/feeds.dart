import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/event.dart';
import '../models/job.dart';

/// Inhalt einer der drei Dateien (events.json, freizeit.json, jobs.json).
class FeedData {
  FeedData(this.generated, {this.events = const [], this.jobs = const []});
  final DateTime generated;
  final List<OpenDayEvent> events;
  final List<Job> jobs;

  Iterable<String> get ids => [...events.map((e) => e.id), ...jobs.map((j) => j.id)];

  static FeedData? parse(String body, String file) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['version'] != 1) return null;
      final generated = DateTime.parse(j['generated'] as String);
      if (file == 'jobs.json') {
        final jobs = <Job>[
          for (final raw in (j['jobs'] as List? ?? const []))
            if (raw is Map<String, dynamic>) ?Job.tryParse(raw),
        ];
        return FeedData(generated, jobs: jobs);
      }
      final area = Area.values.firstWhere((a) => a.file == file, orElse: () => Area.offeneTuer);
      final events = <OpenDayEvent>[
        for (final raw in (j['events'] as List? ?? const []))
          if (raw is Map<String, dynamic>) ?OpenDayEvent.tryParse(raw, area),
      ];
      return FeedData(generated, events: events);
    } catch (_) {
      return null;
    }
  }
}

/// Laden, Zwischenspeichern und Aktualisieren der Dateien.
class FeedStore {
  static const files = ['events.json', 'freizeit.json', 'jobs.json'];

  static Future<File> _cache(String file) async {
    final dir = await getApplicationSupportDirectory();
    // events.json hieß früher events_cache.json – Name beibehalten, damit nichts verloren geht
    final name = file == 'events.json' ? 'events_cache.json' : '${file.replaceAll('.json', '')}_cache.json';
    return File('${dir.path}/$name');
  }

  /// Bester lokaler Stand: gespeicherte Datei oder mitgelieferte, je nachdem was neuer ist.
  static Future<FeedData?> loadLocal(String file) async {
    FeedData? cached, bundled;
    try {
      final f = await _cache(file);
      if (await f.exists()) cached = FeedData.parse(await f.readAsString(), file);
    } catch (_) {}
    try {
      bundled = FeedData.parse(await rootBundle.loadString('assets/$file'), file);
    } catch (_) {}
    if (cached == null) return bundled;
    if (bundled == null) return cached;
    return bundled.generated.isAfter(cached.generated) ? bundled : cached;
  }

  /// Holt die Datei aus dem Netz. Gibt null zurück, wenn sie nicht neuer ist.
  /// Wirft bei Netzwerkfehlern.
  static Future<FeedData?> fetch(String base, String file, {DateTime? newerThan}) async {
    final b = base.endsWith('/') ? base : '$base/';
    final res = await http
        .get(Uri.parse('$b$file'), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null; // Datei gibt es (noch) nicht
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final body = utf8.decode(res.bodyBytes);
    final data = FeedData.parse(body, file);
    if (data == null) throw const FormatException('Datei hat ein unbekanntes Format');
    if (newerThan != null && data.generated.isBefore(newerThan)) return null;
    await (await _cache(file)).writeAsString(body, flush: true);
    return data;
  }
}
