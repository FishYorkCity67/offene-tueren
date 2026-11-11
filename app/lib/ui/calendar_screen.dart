import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/event.dart';
import '../services/actions.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'event_sheet.dart';
import 'widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.bottomInset});
  final double bottomInset;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _today = _dateOnly(DateTime.now());
  late DateTime _focused = _today;
  late DateTime _selected = _today;
  PageController? _pages;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _first => DateTime(_today.year, _today.month, 1);
  DateTime get _last => _today.add(const Duration(days: 400));

  void _select(DateTime day) {
    setState(() {
      _selected = _dateOnly(day);
      _focused = _selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    _today = _dateOnly(DateTime.now());

    // Tage -> Kategorien (für die Punkte) einmal vorberechnen
    final byDay = <DateTime, List<OpenDayEvent>>{};
    for (final e in s.calendarEvents) {
      for (final d in e.days) {
        (byDay[d] ??= []).add(e);
      }
    }
    final dayEvents = s.eventsOn(_selected);
    final nextDay = (byDay.keys.where((d) => d.isAfter(_selected)).toList()..sort()).firstOrNull;
    final monthTitle = DateFormat('MMMM y', 'de_DE').format(_focused);

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top + 12)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: p.outline),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
                child: Row(children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.medium),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: c),
                      ),
                      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                      child: Text(monthTitle, key: ValueKey(monthTitle), style: t.headlineSmall),
                    ),
                  ),
                  if (!isSameDay(_selected, _today))
                    TextButton(onPressed: () => _select(_today), child: const Text('Heute')),
                  RoundIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Voriger Monat',
                    onTap: () => _pages?.previousPage(duration: Motion.medium, curve: Motion.curve),
                  ),
                  RoundIconButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Nächster Monat',
                    onTap: () => _pages?.nextPage(duration: Motion.medium, curve: Motion.curve),
                  ),
                ]),
              ),
              TableCalendar<OpenDayEvent>(
                locale: 'de_DE',
                firstDay: _first,
                lastDay: _last,
                focusedDay: _focused.isBefore(_first) ? _first : _focused,
                headerVisible: false,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableGestures: AvailableGestures.horizontalSwipe,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Monat'},
                rowHeight: 50,
                daysOfWeekHeight: 26,
                pageAnimationDuration: Motion.of(context, Motion.medium),
                pageAnimationCurve: Motion.curve,
                onCalendarCreated: (c) => _pages = c,
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                eventLoader: (d) => byDay[_dateOnly(d)] ?? const [],
                onDaySelected: (sel, _) => _select(sel),
                onPageChanged: (f) => setState(() => _focused = f),
                daysOfWeekStyle: DaysOfWeekStyle(
                  dowTextFormatter: (d, l) => DateFormat.E(l).format(d).substring(0, 2),
                  weekdayStyle: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
                  weekendStyle: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
                ),
                calendarBuilders: CalendarBuilders<OpenDayEvent>(
                  defaultBuilder: (ctx, day, _) => _DayCell(day: day),
                  todayBuilder: (ctx, day, _) => _DayCell(day: day, today: true),
                  selectedBuilder: (ctx, day, _) => _DayCell(day: day, selected: true, today: isSameDay(day, _today)),
                  outsideBuilder: (ctx, day, _) => _DayCell(day: day, outside: true),
                  disabledBuilder: (ctx, day, _) => _DayCell(day: day, outside: true),
                  markerBuilder: (ctx, day, events) => events.isEmpty ? null : _Dots(events: events),
                ),
              ),
            ]),
          ),
        ),
      ),

      // ---- Tagesliste -------------------------------------------------------------------
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('EEEE, d. MMMM', 'de_DE').format(_selected), style: t.titleLarge),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                  dayEvents.isEmpty
                      ? 'Keine Termine an diesem Tag'
                      : '${dayEvents.length} ${dayEvents.length == 1 ? 'Termin' : 'Termine'} · '
                          '${s.myLocation != null ? 'nach Entfernung sortiert' : 'nach Uhrzeit sortiert'}',
                  style: t.bodySmall,
                ),
              ),
              if (s.myLocation == null && dayEvents.length > 1)
                TextButton.icon(
                  onPressed: () => s.locate(),
                  icon: const Icon(Icons.near_me_outlined, size: 16),
                  label: const Text('Standort nutzen'),
                ),
            ]),
          ]),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, widget.bottomInset + 24),
        sliver: dayEvents.isEmpty
            ? SliverToBoxAdapter(
                child: Appear(
                  key: ValueKey('empty$_selected'),
                  child: EmptyState(
                    icon: Icons.event_busy_rounded,
                    title: 'Hier ist frei',
                    text: nextDay != null
                        ? 'Der nächste Termin ist am ${DateFormat('EEEE, d. MMMM', 'de_DE').format(nextDay)}.'
                        : 'Danach sind noch keine Termine bekannt.',
                    action: nextDay == null
                        ? null
                        : OutlinedButton(onPressed: () => _select(nextDay), child: const Text('Zum nächsten Termin')),
                  ),
                ),
              )
            : SliverList.separated(
                itemCount: dayEvents.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final e = dayEvents[i];
                  return Appear(
                    key: ValueKey('${e.id}$_selected'),
                    index: i,
                    child: EventTile(
                      event: e,
                      showDate: e.isMultiDay,
                      onTap: () => showEventSheet(context, e),
                      trailing: RoundIconButton(
                        icon: Icons.edit_calendar_outlined,
                        tooltip: 'In meinen Handy-Kalender eintragen',
                        onTap: () => EventActions.addToCalendar(context, e),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, this.selected = false, this.today = false, this.outside = false});
  final DateTime day;
  final bool selected;
  final bool today;
  final bool outside;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        width: 38,
        height: 38,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? p.ink : Colors.transparent,
          shape: BoxShape.circle,
          border: today && !selected ? Border.all(color: p.ink, width: 1.4) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.onInk : (outside ? p.muted.withValues(alpha: 0.45) : p.ink),
          ),
        ),
      ),
    );
  }
}

/// Bis zu vier Punkte unter dem Tag – je Kategorie einer.
class _Dots extends StatelessWidget {
  const _Dots({required this.events});
  final List<OpenDayEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cats = Category.values.where((c) => events.any((e) => e.category == c)).toList();
    return Positioned(
      bottom: 4,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final c in cats)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: p.category(c), shape: BoxShape.circle),
          ),
      ]),
    );
  }
}
