import 'package:add_2_calendar/add_2_calendar.dart' as cal;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';

class EventActions {
  /// Öffnet Google Maps mit einer Route zum Termin.
  static Future<void> route(BuildContext context, OpenDayEvent e) async {
    final dest = e.point != null
        ? '${e.point!.latitude},${e.point!.longitude}'
        : Uri.encodeComponent([e.org, e.address, e.city].where((s) => s.isNotEmpty).join(', '));
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=transit');
    await _open(context, uri);
  }

  static Future<void> website(BuildContext context, OpenDayEvent e) async {
    final uri = Uri.tryParse(e.url);
    if (uri == null || !uri.hasScheme) {
      _snack(context, 'Für diesen Termin gibt es keinen Link.');
      return;
    }
    await _open(context, uri);
  }

  /// Öffnet die Kalender-App mit einem vorausgefüllten Termin.
  static Future<void> addToCalendar(BuildContext context, OpenDayEvent e) async {
    final location = [e.address, if (!e.address.contains(e.city)) e.city].where((s) => s.isNotEmpty).join(', ');
    final desc = [
      e.kind,
      if (e.description.isNotEmpty) e.description,
      if (e.needsAdult) 'Hinweis: Begleitung durch eine erwachsene Person nötig.',
      if (e.url.isNotEmpty) e.url,
    ].join('\n\n');
    final event = cal.Event(
      title: e.title == e.org || e.org.isEmpty ? e.title : '${e.title} – ${e.org}',
      description: desc,
      location: location.isEmpty ? null : location,
      startDate: e.allDay ? DateTime(e.start.year, e.start.month, e.start.day) : e.start,
      endDate: e.allDay ? DateTime(e.end.year, e.end.month, e.end.day, 23, 59) : e.end,
      allDay: e.allDay,
      timeZone: 'Europe/Berlin',
    );
    final ok = await cal.Add2Calendar.addEvent2Cal(event);
    if (!ok && context.mounted) _snack(context, 'Keine Kalender-App gefunden.');
  }

  static Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _snack(context, 'Link konnte nicht geöffnet werden.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Link konnte nicht geöffnet werden.');
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
