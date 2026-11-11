import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';

/// Erinnerungen einen Tag vor gemerkten Terminen (um 18 Uhr am Vortag).
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Erinnerungen',
    channelDescription: 'Erinnert dich einen Tag vor gemerkten Terminen',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    color: _brandColor,
    icon: 'ic_stat_door',
  );

  // Jade wie in der App
  static const _brandColor = Color(0xFF1D7357);

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_door')),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  static int _idFor(OpenDayEvent e) => e.id.hashCode & 0x7fffffff;

  /// Plant genau die Erinnerungen für [events] neu (alte werden gelöscht).
  Future<void> sync(List<OpenDayEvent> events) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    final fmt = DateFormat('EEEE, d. MMMM', 'de_DE');
    for (final e in events) {
      final day = tz.TZDateTime(tz.local, e.start.year, e.start.month, e.start.day);
      final at = day.subtract(const Duration(days: 1)).add(const Duration(hours: 18));
      if (!at.isAfter(now)) continue;
      final time = e.allDay ? '' : ', ${DateFormat.Hm('de_DE').format(e.start)} Uhr';
      await _plugin.zonedSchedule(
        id: _idFor(e),
        title: 'Morgen: ${e.headline}',
        body: '${e.kind} · ${fmt.format(e.start)}$time${e.city.isNotEmpty ? ' · ${e.city}' : ''}',
        scheduledDate: at,
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: e.id,
      );
    }
  }
}
