import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Die großen Bereiche der App. Jeder Bereich kommt aus einer eigenen JSON-Datei.
enum Area {
  offeneTuer('offene-tueren', 'Tag der offenen Tür', 'Offene Türen', 'events.json', Icons.door_front_door_outlined),
  freizeit('freizeit', 'Freizeit & Events', 'Freizeit', 'freizeit.json', Icons.local_activity_outlined);

  const Area(this.id, this.label, this.short, this.file, this.icon);
  final String id;
  final String label;
  final String short;
  final String file;
  final IconData icon;

  List<Category> get categories => Category.values.where((c) => c.area == this).toList();
}

/// Unterkategorien. Die `id` steht so auch in den JSON-Dateien (siehe crawler/feeds/*.yaml).
enum Category {
  hochschule('hochschule', 'Unis & Hochschulen', 'Hochschule', Icons.school_rounded, Area.offeneTuer),
  schule('schule', 'Schulen', 'Schule', Icons.backpack_rounded, Area.offeneTuer),
  ausbildung('ausbildung', 'Firmen & Ausbildung', 'Ausbildung', Icons.handyman_rounded, Area.offeneTuer),
  sonstiges('sonstiges', 'Behörden & Sonstiges', 'Sonstiges', Icons.account_balance_rounded, Area.offeneTuer),
  gratis('gratis', 'Gratis-Events', 'Gratis', Icons.celebration_rounded, Area.freizeit),
  flohmarkt('flohmarkt', 'Flohmärkte', 'Flohmarkt', Icons.storefront_rounded, Area.freizeit),
  ferienprogramm('ferienprogramm', 'Ferienprogramme', 'Ferien', Icons.wb_sunny_rounded, Area.freizeit),
  saisonal('saisonal', 'Saisonales', 'Saisonal', Icons.festival_rounded, Area.freizeit);

  const Category(this.id, this.label, this.short, this.icon, this.area);

  final String id;
  final String label;
  final String short;
  final IconData icon;
  final Area area;

  static Category fromId(String? id, Area area) => Category.values.firstWhere(
        (c) => c.id == id && c.area == area,
        orElse: () => area == Area.freizeit ? Category.gratis : Category.sonstiges,
      );
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
    this.free,
    this.price = '',
    this.openingHours = '',
    this.daily = false,
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

  /// true = gratis, false = kostet etwas, null = unbekannt
  final bool? free;
  final String price;
  final String openingHours;

  /// Mehrtägig und die Uhrzeiten gelten an jedem Tag (z. B. Weihnachtsmarkt 11–21 Uhr).
  final bool daily;

  Area get area => category.area;

  /// Überschrift in Listen. Bei Freizeit ist der Titel aussagekräftiger als der Veranstalter.
  String get headline {
    if (area == Area.freizeit) return title.isNotEmpty ? title : org;
    return org.isNotEmpty ? org : title;
  }

  /// Unterzeile: Art der Veranstaltung bzw. Veranstalter.
  String get kind {
    if (area == Area.freizeit) return org.isNotEmpty && org != title ? org : category.label;
    return title.isNotEmpty && title != org ? title : category.short;
  }

  bool get isMultiDay => !_sameDay(start, end);

  /// Läuft gerade bzw. hat gerade offen?
  bool isLive(DateTime now) {
    if (daily) {
      // jeden Tag im Zeitraum von Startzeit bis Endzeit geöffnet
      if (!occursOn(now)) return false;
      final open = DateTime(now.year, now.month, now.day, start.hour, start.minute);
      var close = DateTime(now.year, now.month, now.day, end.hour, end.minute);
      if (!close.isAfter(open)) close = DateTime(now.year, now.month, now.day, 23, 59);
      return now.isAfter(open) && now.isBefore(close);
    }
    // Mehrtägig ohne tägliche Zeiten (z. B. Ausstellung): Öffnungszeiten unbekannt -> nie "Jetzt",
    // stattdessen zeigt die Liste "bis …".
    if (isMultiDay) return false;
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
    while (!d.isAfter(last) && guard++ < 120) {
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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Die Zeiten in den JSON-Dateien sind deutsche Ortszeit mit Versatz ("2027-01-16T10:00:00+01:00").
  /// Wir nehmen genau die Uhrzeit, die dort steht – unabhängig von der Zeitzone des Handys.
  static DateTime berlinWallTime(String s) {
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?)').firstMatch(s);
    return m != null ? DateTime.parse(m.group(1)!) : DateTime.parse(s).toLocal();
  }

  static OpenDayEvent? tryParse(Map<String, dynamic> j, Area area) {
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
        category: Category.fromId(j['category'] as String?, area),
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
        free: j['free'] as bool?,
        price: (j['price'] as String?) ?? '',
        openingHours: (j['openingHours'] as String?) ?? '',
        daily: j['daily'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
