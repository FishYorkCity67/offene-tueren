import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Art der Arbeit (ids wie in crawler/jobs.py).
enum JobType {
  austragen('austragen', 'Austragen', Icons.mail_outline_rounded),
  nachhilfe('nachhilfe', 'Nachhilfe', Icons.menu_book_rounded),
  babysitten('babysitten', 'Babysitten', Icons.child_care_rounded),
  garten('garten', 'Garten', Icons.yard_outlined),
  tiere('tiere', 'Tiere', Icons.pets_rounded),
  einkauf('einkauf', 'Einkaufshilfe', Icons.shopping_basket_outlined),
  verkauf('verkauf', 'Verkauf', Icons.point_of_sale_rounded),
  gastro('gastro', 'Gastronomie', Icons.local_cafe_outlined),
  lager('lager', 'Lager & Helfer', Icons.inventory_2_outlined),
  buero('buero', 'Büro', Icons.desk_outlined),
  sonstiges('sonstiges', 'Sonstiges', Icons.work_outline_rounded);

  const JobType(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  static JobType fromId(String? id) =>
      JobType.values.firstWhere((t) => t.id == id, orElse: () => JobType.sonstiges);
}

/// Altersstufen nach dem Jugendarbeitsschutzgesetz.
String ageClassLabel(int minAge) => switch (minAge) {
      <= 14 => 'ab 13/14 möglich',
      15 => 'ab 15',
      16 => 'ab 16',
      _ => 'ab 18',
    };

class Job {
  Job({
    required this.id,
    required this.title,
    required this.employer,
    required this.type,
    required this.minAge,
    required this.ageReason,
    required this.city,
    required this.address,
    required this.point,
    required this.hours,
    required this.pay,
    required this.payPerHour,
    required this.period,
    required this.start,
    required this.url,
    required this.contact,
    required this.description,
    required this.source,
    required this.firstSeen,
  });

  final String id;
  final String title;
  final String employer;
  final JobType type;
  final int minAge;
  final String ageReason;
  final String city;
  final String address;
  final LatLng? point;
  final String hours;
  final String pay;
  final double? payPerHour;
  final String period;
  final DateTime? start;
  final String url;
  final String contact;
  final String description;
  final String source;
  final DateTime? firstSeen;

  bool allowedFor(int age) => minAge <= age;

  static Job? tryParse(Map<String, dynamic> j) {
    try {
      final lat = (j['lat'] as num?)?.toDouble();
      final lng = (j['lng'] as num?)?.toDouble();
      return Job(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        employer: (j['employer'] as String?) ?? '',
        type: JobType.fromId(j['type'] as String?),
        minAge: (j['minAge'] as num?)?.toInt() ?? 18,
        ageReason: (j['ageReason'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        point: lat != null && lng != null ? LatLng(lat, lng) : null,
        hours: (j['hours'] as String?) ?? '',
        pay: (j['pay'] as String?) ?? '',
        payPerHour: (j['payPerHour'] as num?)?.toDouble(),
        period: (j['period'] as String?) ?? 'Nebenbei',
        start: DateTime.tryParse((j['start'] as String?) ?? ''),
        url: (j['url'] as String?) ?? '',
        contact: (j['contact'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        source: (j['source'] as String?) ?? '',
        firstSeen: DateTime.tryParse((j['firstSeen'] as String?) ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}
