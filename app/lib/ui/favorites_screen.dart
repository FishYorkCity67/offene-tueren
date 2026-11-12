import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/event.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'event_sheet.dart';
import 'job_sheet.dart';
import 'jobs_screen.dart';
import 'widgets.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.bottomInset});
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final favs = s.favoriteEvents;
    final favJobs = s.favoriteJobs;
    final total = favs.length + favJobs.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 18, 16, bottomInset + 28),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gemerkt', style: t.headlineMedium),
            const SizedBox(height: 4),
            Text(
              total == 0
                  ? 'Deine Favoriten erscheinen hier.'
                  : '$total gemerkt${s.reminders && favs.isNotEmpty ? ' · Erinnerung am Vortag an' : ''}',
              style: t.bodySmall,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (total == 0)
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.outline),
            ),
            child: const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Noch nichts gemerkt',
              text: 'Tippe bei einem Termin, Event oder Job auf das Herz – dann findest du ihn hier. '
                  'Für Termine bekommst du am Tag davor eine Erinnerung.',
            ),
          ),
        for (final (i, e) in favs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Appear(
              key: ValueKey('fav${e.id}'),
              index: i,
              child: EventTile(
                event: e,
                onTap: () => showEventSheet(context, e),
                trailing: RoundIconButton(
                  icon: Icons.favorite_rounded,
                  color: p.category(Category.sonstiges),
                  tooltip: 'Entfernen',
                  onTap: () => s.toggleFavorite(e),
                ),
              ),
            ),
          ),
        if (favJobs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
            child: Text('Gemerkte Jobs', style: t.titleMedium),
          ),
          for (final j in favJobs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: JobTile(
                job: j,
                trailing: RoundIconButton(
                  icon: Icons.favorite_rounded,
                  color: p.category(Category.sonstiges),
                  tooltip: 'Entfernen',
                  onTap: () => s.toggleFavoriteId(j.id, remind: false),
                ),
              ),
            ),
        ],
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('Einstellungen', style: t.headlineSmall),
        ),
        const SizedBox(height: 12),

        // ---- Über mich ---------------------------------------------------------------------
        _Group(children: [
          _Row(
            icon: Icons.cake_outlined,
            title: 'Mein Alter',
            subtitle: 'Termine und Jobs mit höherer Altersgrenze werden ausgeblendet'
                '${s.hiddenByAge + s.jobsTooYoung > 0 ? ' (gerade ${s.hiddenByAge + s.jobsTooYoung})' : ''}',
            trailing: _Stepper(value: s.age, onChanged: s.setAge),
          ),
          _Row(
            icon: Icons.radar_rounded,
            title: 'Suchradius für Karte & Kalender',
            subtitle: _radiusHint(s),
            below: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final km in const [10, 25, 50, 100, null])
                ChoicePill(
                  label: km == null ? 'Ganz Deutschland' : '$km km',
                  selected: s.radiusKm == km,
                  onTap: () async {
                    await s.setRadius(km);
                    if (km != null && s.myLocation == null) await s.locate();
                  },
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        // ---- Was ich sehen will -----------------------------------------------------------
        _SectionTitle('Was ich auf Karte & Kalender sehen will'),
        _Group(children: [
          for (final a in Area.values)
            _Row(
              icon: a.icon,
              title: a.label,
              trailing: Switch(
                value: a.categories.any(s.categoryVisible),
                onChanged: (v) => s.setAreaVisible(a, v),
              ),
              below: a.categories.any(s.categoryVisible)
                  ? Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final c in a.categories)
                        ChoicePill(
                          label: c.label,
                          icon: c.icon,
                          selected: s.categoryVisible(c),
                          onTap: () => s.setCategoryVisible(c, !s.categoryVisible(c)),
                        ),
                    ])
                  : null,
            ),
        ]),
        const SizedBox(height: 14),

        // ---- Mitteilungen -----------------------------------------------------------------
        _SectionTitle('Mitteilungen'),
        _Group(children: [
          _Row(
            icon: Icons.notifications_none_rounded,
            title: 'Erinnerung am Vortag',
            subtitle: 'Um 18 Uhr für jeden gemerkten Termin',
            trailing: Switch(value: s.reminders, onChanged: s.setReminders),
          ),
          _Row(
            icon: Icons.door_front_door_outlined,
            title: 'Neue Tage der offenen Tür',
            subtitle: 'in ${s.notifyRadiusKm} km Umkreis',
            trailing: Switch(value: s.notifyOffene, onChanged: (v) => s.setNotify(offene: v)),
          ),
          _Row(
            icon: Icons.local_activity_outlined,
            title: 'Neue Freizeit-Events',
            subtitle: 'in ${s.notifyRadiusKm} km Umkreis',
            trailing: Switch(value: s.notifyFreizeit, onChanged: (v) => s.setNotify(freizeit: v)),
          ),
          _Row(
            icon: Icons.work_outline_rounded,
            title: 'Neue Ferienjobs',
            subtitle: 'in ${s.notifyRadiusKm} km Umkreis, passend zu deinem Alter',
            trailing: Switch(value: s.notifyJobs, onChanged: (v) => s.setNotify(jobs: v)),
          ),
          _Row(
            icon: Icons.near_me_outlined,
            title: 'Umkreis für Mitteilungen',
            subtitle: s.myLocation == null
                ? 'Braucht deinen Standort – sonst kommt keine „in deiner Nähe“-Mitteilung'
                : 'Geprüft wird beim Öffnen der App und etwa alle 6 Stunden',
            below: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final km in const [5, 10, 25, 50])
                ChoicePill(label: '$km km', selected: s.notifyRadiusKm == km, onTap: () => s.setNotify(radius: km)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        // ---- Darstellung ------------------------------------------------------------------
        _SectionTitle('Darstellung'),
        _Group(children: [
          _Row(
            icon: Icons.contrast_rounded,
            title: 'Hell oder dunkel',
            below: SegmentPill<ThemeMode>(
              values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
              selected: s.themeMode,
              label: (m) => switch (m) { ThemeMode.light => 'Hell', ThemeMode.dark => 'Dunkel', _ => 'System' },
              onChanged: s.setThemeMode,
            ),
          ),
          _Row(
            icon: Icons.map_outlined,
            title: 'Ruhige Karte',
            subtitle: s.calmMap ? 'Gedämpfte Kartenfarben, damit die Pins gut auffallen' : 'Kräftige Farben wie bei OpenStreetMap',
            trailing: Switch(value: s.calmMap, onChanged: s.setCalmMap),
          ),
        ]),
        const SizedBox(height: 14),

        // ---- Daten ------------------------------------------------------------------------
        _Group(children: [
          _Row(
            icon: Icons.cloud_sync_outlined,
            title: 'Daten',
            subtitle: _sourceHint(s),
            below: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: s.dataBase.isEmpty || s.refreshing ? null : s.refresh,
                  icon: s.refreshing
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onInk))
                      : const Icon(Icons.refresh_rounded, size: 19),
                  label: const Text('Aktualisieren'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: () => _editSource(context, s), child: const Text('Quelle')),
            ]),
          ),
          _Row(
            icon: Icons.gavel_rounded,
            title: 'Was darf ich arbeiten?',
            subtitle: 'Jugendarbeitsschutz kurz erklärt',
            trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
            onTap: () => showJobRules(context),
          ),
        ]),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${AppConfig.appName} sammelt Termine, Events und Jobs jeden Tag automatisch von öffentlichen '
            'Websites und der Jobbörse der Bundesagentur für Arbeit. Angebote nur für Fachpublikum oder '
            'Erwachsene sind ausgeblendet. Alle Angaben ohne Gewähr.\n'
            'Karte © OpenStreetMap-Mitwirkende (ODbL), Kartenkacheln von openstreetmap.org.',
            style: t.bodySmall,
          ),
        ),
      ],
    );
  }

  static String _radiusHint(AppState s) {
    if (s.radiusKm == null) return 'Zeigt alles in ganz Deutschland';
    return switch (s.locationStatus) {
      LocationStatus.denied => 'Ohne Standort-Erlaubnis gilt der Radius nicht',
      LocationStatus.off => 'Standort ist aus – der Radius gilt erst, wenn er an ist',
      _ when s.myLocation == null => 'Wird angewendet, sobald dein Standort bekannt ist',
      _ => 'Nur Einträge bis ${s.radiusKm} km um dich herum',
    };
  }

  static String _sourceHint(AppState s) {
    final g = s.generated;
    final stand = g != null ? 'Stand ${DateFormat('d. MMM, HH:mm', 'de_DE').format(g.toLocal())} Uhr' : 'Noch nicht geladen';
    final counts = '${s.countIn(Area.offeneTuer)} Tage der offenen Tür · ${s.countIn(Area.freizeit)} Events · ${s.jobCount} Jobs';
    return s.fetchError != null ? '$stand · ${s.fetchError}' : '$stand\n$counts';
  }

  Future<void> _editSource(BuildContext context, AppState s) async {
    final ctl = TextEditingController(text: s.dataBase);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datenquelle'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ordner mit events.json, freizeit.json und jobs.json – z. B. die „Raw“-Adresse '
              'des data-Ordners in deinem GitHub-Projekt.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://raw.githubusercontent.com/…/data/'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => ctl.text = kDefaultDataBase, child: const Text('Standard')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Speichern')),
        ],
      ),
    );
    ctl.dispose();
    if (url != null) await s.setDataBase(url);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: p.muted)),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.outline),
      ),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Padding(padding: const EdgeInsets.only(left: 62), child: Divider(color: p.outline)),
          children[i],
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, this.below, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: p.inkSoft),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.fast),
                  child: Text(subtitle!, key: ValueKey(subtitle), style: t.bodySmall),
                ),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
        AnimatedSize(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: below != null
              ? Padding(padding: const EdgeInsets.only(left: 48, top: 12), child: below!)
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        RoundIconButton(icon: Icons.remove_rounded, size: 38, onTap: () => onChanged(value - 1), tooltip: 'Jünger'),
        SizedBox(
          width: 26,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text('$value',
                key: ValueKey(value),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: p.ink)),
          ),
        ),
        RoundIconButton(icon: Icons.add_rounded, size: 38, onTap: () => onChanged(value + 1), tooltip: 'Älter'),
      ]),
    );
  }
}
