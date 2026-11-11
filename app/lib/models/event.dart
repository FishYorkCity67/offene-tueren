import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Die vier Arten von Einrichtungen. Die `id` steht so auch in events.json.
enum Category {
  hochschule('hochschule', 'Unis & Hochschulen', 'Hochschule', Icons.school_rounded),
  schule('schule', 'Schulen', 'Schule', Icons.backpack_rounded),
  ausbildung('ausbildung', 'Firmen & Ausbildung', 'Ausbildung', Icons.handyman_rounded),
  sonstiges('sonstiges', 'Behörden & Sonstiges', 'Sonstiges', Icons.account_balance_rounded);

  const Category(this.id, this.label, this.short, this.icon);

  final String id;
  final String label;
  final String short;
  final IconData icon;

  static Category fromId(String? id) =>
      Category.values.firstWhere((c) => c.id == id, orElse: () => Category.sonstiges);
}

class OpenDayEvent {
  OpenDayEvent({
    required this.id,
    required this.title,
    required this.org,
    required this.category,
    required this.start,
    required this.end,
    required this.allDay,
    required this.address,
    required this.city,
    required this.point,
    required this.url,
    required this.minAge,
    required this.audience,
    required this.needsAdult,
    required this.description,
    required this.verified,
  });

  final String id;
  final String title;
  final String org;
  final Category category;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String address;
  final String city;
  final LatLng? point;
  final String url;
  final int? minAge;
  final String audience;
  final bool needsAdult;
  final String description;
  final bool verified;

  /// Überschrift, die in Listen steht: Name der Einrichtung, sonst der Titel.
  String get headline => org.isNotEmpty ? org : title;

  /// Unterzeile: Art der Veranstaltung, wenn sie sich vom Namen unterscheidet.
  String get kind => title.isNotEmpty && title != org ? title : category.short;

  bool get isMultiDay => !_sameDay(start, end);

  /// Läuft gerade? Ganztägige Termine zählen von 8 bis 18 Uhr als „jetzt“.
  bool isLive(DateTime now) {
    if (allDay) {
      final s = DateTime(start.year, start.month, start.day, 8);
      final e = DateTime(end.year, end.month, end.day, 18);
      return now.isAfter(s) && now.isBefore(e);
    }
    return now.isAfter(start) && now.isBefore(end);
  }

  bool isPast(DateTime now) => end.isBefore(now);

  /// Alle Kalendertage, die der Termin berührt.
  Iterable<DateTime> get days sync* {
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    var guard = 0;
    while (!d.isAfter(last) && guard++ < 31) {
      yield d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
  }

  bool occursOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// Darf jemand mit [age] Jahren hin? Fachpublikum ist schon im Crawler aussortiert.
  bool allowedFor(int age) {
    if (audience == 'fachpublikum') return false;
    if (audience == 'erwachsene' && age < 18) return false;
    return minAge == null || minAge! <= age;
  }

  /// Die Zeiten in events.json sind deutsche Ortszeit mit Versatz ("2027-01-16T10:00:00+01:00").
  /// Wir nehmen genau die Uhrzeit, die dort steht – unabhängig von der Zeitzone des Handys.
  static DateTime berlinWallTime(String s) {
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?)').firstMatch(s);
    return m != null ? DateTime.parse(m.group(1)!) : DateTime.parse(s).toLocal();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static OpenDayEvent? tryParse(Map<String, dynamic> j) {
    try {
      final start = berlinWallTime(j['start'] as String);
      var end = j['end'] != null ? berlinWallTime(j['end'] as String) : start;
      if (end.isBefore(start)) end = start;
      final lat = (j['lat'] as num?)?.toDouble();
      final lng = (j['lng'] as num?)?.toDouble();
      return OpenDayEvent(
        id: j['id'] as String,
        title: (j['title'] as String?)?.trim() ?? '',
        org: (j['org'] as String?)?.trim() ?? '',
        category: Category.fromId(j['category'] as String?),
        start: start,
        end: end,
        allDay: j['allDay'] == true,
        address: (j['address'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        point: lat != null && lng != null ? LatLng(lat, lng) : null,
        url: (j['url'] as String?) ?? '',
        minAge: (j['minAge'] as num?)?.toInt(),
        audience: (j['audience'] as String?) ?? 'alle',
        needsAdult: j['needsAdult'] == true,
        description: (j['description'] as String?) ?? '',
        verified: j['verified'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
