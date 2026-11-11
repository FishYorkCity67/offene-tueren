import 'package:intl/intl.dart';

import '../models/event.dart';

final _wdDay = DateFormat('EEE, d. MMM', 'de_DE');
final _dayMonth = DateFormat('d. MMM', 'de_DE');
final _long = DateFormat('EEEE, d. MMMM y', 'de_DE');
final _hm = DateFormat('H:mm', 'de_DE');

String _clock(DateTime t) => t.minute == 0 ? '${t.hour}' : _hm.format(t);

/// "10–14 Uhr", "ab 18:30 Uhr" oder "ganztägig".
String timeRange(OpenDayEvent e) {
  if (e.allDay) return 'ganztägig';
  final sameMoment = e.end.difference(e.start).inMinutes <= 0;
  final endIsMarker = e.end.hour == 23 && e.end.minute == 59;
  if (sameMoment || endIsMarker || e.isMultiDay) return 'ab ${_clock(e.start)} Uhr';
  return '${_clock(e.start)}–${_clock(e.end)} Uhr';
}

/// "Sa., 24. Jan." bzw. "27.–28. Jan." bei mehrtägigen Terminen.
String dateShort(OpenDayEvent e) {
  if (!e.isMultiDay) return _wdDay.format(e.start);
  if (e.start.month == e.end.month) return '${e.start.day}.–${_dayMonth.format(e.end)}';
  return '${_dayMonth.format(e.start)} – ${_dayMonth.format(e.end)}';
}

String dateLong(OpenDayEvent e) {
  if (!e.isMultiDay) return _long.format(e.start);
  return '${_long.format(e.start)} bis\n${_long.format(e.end)}';
}

String dateAndTime(OpenDayEvent e) => '${dateShort(e)} · ${timeRange(e)}';

String distance(double? km) {
  if (km == null) return '';
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${km.round()} km';
}

/// "heute", "morgen", "in 5 Tagen" – nur für die nächsten zwei Wochen.
String relativeDay(OpenDayEvent e, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(e.start.year, e.start.month, e.start.day);
  final diff = d.difference(today).inDays;
  if (e.isLive(now)) return 'läuft gerade';
  if (diff <= 0 && e.occursOn(today)) return 'heute';
  if (diff == 1) return 'morgen';
  if (diff > 1 && diff <= 14) return 'in $diff Tagen';
  return '';
}

String audienceLabel(String a) => switch (a) {
      'schueler' => 'für Schülerinnen und Schüler',
      'studieninteressierte' => 'für Studieninteressierte',
      'familien' => 'für Familien',
      _ => 'für alle',
    };
