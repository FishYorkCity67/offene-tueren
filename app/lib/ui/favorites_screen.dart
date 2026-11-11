import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'event_sheet.dart';
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

    return ListView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 18, 16, bottomInset + 28),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gemerkt', style: t.headlineMedium),
            const SizedBox(height: 4),
            Text(
              favs.isEmpty
                  ? 'Deine Favoriten erscheinen hier.'
                  : '${favs.length} ${favs.length == 1 ? 'Termin' : 'Termine'}${s.reminders ? ' · Erinnerung am Vortag an' : ''}',
              style: t.bodySmall,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (favs.isEmpty)
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.outline),
            ),
            child: const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Noch nichts gemerkt',
              text: 'Tippe bei einem Termin auf „Merken“ – dann findest du ihn hier und wirst am Tag davor erinnert.',
            ),
          )
        else
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
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('Einstellungen', style: t.headlineSmall),
        ),
        const SizedBox(height: 12),
        _Group(children: [
          _Row(
            icon: Icons.notifications_none_rounded,
            title: 'Erinnerung am Vortag',
            subtitle: 'Um 18 Uhr eine Mitteilung für jeden gemerkten Termin',
            trailing: Switch(value: s.reminders, onChanged: s.setReminders),
          ),
          _Row(
            icon: Icons.radar_rounded,
            title: 'Suchradius',
            subtitle: _radiusHint(s),
            below: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final km in const [10, 25, 50, 100, null])
                _Choice(
                  label: km == null ? 'Ganz Deutschland' : '$km km',
                  selected: s.radiusKm == km,
                  onTap: () async {
                    await s.setRadius(km);
                    if (km != null && s.myLocation == null) await s.locate();
                  },
                ),
            ]),
          ),
          _Row(
            icon: Icons.contrast_rounded,
            title: 'Darstellung',
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
          _Row(
            icon: Icons.cake_outlined,
            title: 'Mein Alter',
            subtitle: s.hiddenByAge == 0
                ? 'Termine mit höherer Altersgrenze werden ausgeblendet'
                : '${s.hiddenByAge} ${s.hiddenByAge == 1 ? 'Termin ist' : 'Termine sind'} erst ab einem höheren Alter erlaubt und ausgeblendet',
            trailing: _Stepper(value: s.age, onChanged: s.setAge),
          ),
        ]),
        const SizedBox(height: 14),
        _Group(children: [
          _Row(
            icon: Icons.cloud_sync_outlined,
            title: 'Termine',
            subtitle: _sourceHint(s),
            below: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: s.sourceUrl.isEmpty || s.refreshing ? null : s.refresh,
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
        ]),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Die Termine sammelt ein Skript jeden Tag automatisch von öffentlichen Websites. '
            'Veranstaltungen nur für Fachpublikum sind ausgeblendet. Angaben ohne Gewähr.\n'
            'Karte © OpenStreetMap-Mitwirkende (ODbL), Kartenkacheln von openstreetmap.org.',
            style: t.bodySmall,
          ),
        ),
      ],
    );
  }

  static String _radiusHint(AppState s) {
    if (s.radiusKm == null) return 'Zeigt Termine in ganz Deutschland';
    return switch (s.locationStatus) {
      LocationStatus.denied => 'Ohne Standort-Erlaubnis gilt der Radius nicht',
      LocationStatus.off => 'Standort ist aus – der Radius gilt erst, wenn er an ist',
      _ when s.myLocation == null => 'Wird angewendet, sobald dein Standort bekannt ist',
      _ => 'Nur Termine bis ${s.radiusKm} km um dich herum',
    };
  }

  static String _sourceHint(AppState s) {
    if (s.sourceUrl.isEmpty) {
      return 'Keine Online-Quelle eingestellt – es werden die mitgelieferten Termine gezeigt.';
    }
    final stand = s.generated != null ? 'Stand ${DateFormat('d. MMM, HH:mm', 'de_DE').format(s.generated!.toLocal())} Uhr' : 'Noch nicht geladen';
    return s.fetchError != null ? '$stand · ${s.fetchError}' : '$stand · ${s.allCount} Einträge';
  }

  Future<void> _editSource(BuildContext context, AppState s) async {
    final ctl = TextEditingController(text: s.sourceUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datenquelle'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Adresse der events.json, z. B. die „Raw“-Adresse aus deinem GitHub-Projekt.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://raw.githubusercontent.com/…/events.json'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Speichern')),
        ],
      ),
    );
    ctl.dispose();
    if (url != null) await s.setSourceUrl(url);
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
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
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, this.below});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
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
        if (below != null) Padding(padding: const EdgeInsets.only(left: 48, top: 12), child: below!),
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.ink : p.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? p.ink : p.outline),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? p.onInk : p.inkSoft)),
      ),
    );
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
