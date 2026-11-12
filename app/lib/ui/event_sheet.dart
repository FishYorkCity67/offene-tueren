import 'package:flutter/material.dart';

import '../models/event.dart';
import '../services/actions.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'format.dart';
import 'widgets.dart';

Future<void> showEventSheet(BuildContext context, OpenDayEvent e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    sheetAnimationStyle: AnimationStyle(
      duration: Motion.of(context, const Duration(milliseconds: 380)),
      reverseDuration: Motion.of(context, const Duration(milliseconds: 220)),
      curve: Curves.easeOutCubic,
    ),
    builder: (_) => EventSheet(event: e),
  );
}

class EventSheet extends StatelessWidget {
  const EventSheet({super.key, required this.event});
  final OpenDayEvent event;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final e = event;
    final now = DateTime.now();
    final km = s.distanceKm(e.point);
    final price = priceLabel(e);
    final place = [
      if (e.address.isNotEmpty) e.address,
      if (e.city.isNotEmpty && !e.address.contains(e.city)) e.city,
    ].join(', ');
    final who = [
      audienceLabel(e.audience),
      if (e.minAge != null) 'ab ${e.minAge} Jahren',
    ].join(' · ');

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + MediaQuery.paddingOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CategoryBadge(e.category, size: 30, filled: true),
            const SizedBox(width: 10),
            Flexible(
              child: Text(e.category.label,
                  overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(color: p.category(e.category))),
            ),
            if (e.isLive(now)) ...[
              const SizedBox(width: 10),
              LiveBadge(label: e.daily ? 'Gerade offen' : 'Jetzt'),
            ],
            const Spacer(),
            _FavButton(event: e),
          ]),
          const SizedBox(height: 14),
          Text(e.headline, style: t.headlineSmall),
          if (e.kind != e.headline) ...[
            const SizedBox(height: 4),
            Text(e.kind, style: t.bodyLarge?.copyWith(color: p.muted)),
          ],
          const SizedBox(height: 18),
          _InfoRow(icon: Icons.calendar_today_rounded, title: dateLong(e), subtitle: timeRange(e)),
          if (e.openingHours.isNotEmpty && timeRange(e) != e.openingHours)
            _InfoRow(icon: Icons.schedule_rounded, title: 'Öffnungszeiten', subtitle: e.openingHours),
          if (price.isNotEmpty)
            _InfoRow(
              icon: e.free == true ? Icons.money_off_rounded : Icons.euro_rounded,
              title: price,
              subtitle: e.free == true ? null : 'Preis laut Veranstalter',
            ),
          if (place.isNotEmpty || km != null)
            _InfoRow(
              icon: Icons.place_outlined,
              title: place.isNotEmpty ? place : 'Ort siehe Website',
              subtitle: km != null ? '${distance(km)} von dir entfernt' : null,
            ),
          _InfoRow(icon: Icons.groups_2_outlined, title: who),
          if (e.needsAdult) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(16)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.family_restroom_rounded, color: p.warn, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Begleitung nötig: Jugendliche dürfen hier nur zusammen mit einer erwachsenen Person teilnehmen.',
                    style: t.bodyMedium?.copyWith(color: p.warn, fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
          ],
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(e.description, style: t.bodyLarge),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => EventActions.route(context, e),
              icon: const Icon(Icons.directions_rounded, size: 20),
              label: const Text('Route planen'),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: e.url.isEmpty ? null : () => EventActions.website(context, e),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Website'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => EventActions.addToCalendar(context, e),
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: const Text('Kalender'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text(
            e.verified
                ? 'Von Hand geprüft. Termine können sich ändern – schau vorher kurz auf die Website.'
                : 'Automatisch gefunden. Angaben ohne Gewähr – bitte vorher auf der Website prüfen.',
            style: t.bodySmall,
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 18, color: p.inkSoft),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleSmall?.copyWith(height: 1.3)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: t.bodySmall),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _FavButton extends StatelessWidget {
  const _FavButton({required this.event});
  final OpenDayEvent event;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final fav = s.isFavorite(event);
    return Material(
      color: fav ? p.categoryTint(Category.sonstiges) : p.surfaceAlt,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () async {
          final added = await s.toggleFavorite(event);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(added
                  ? (s.reminders ? 'Gemerkt – du wirst am Vortag erinnert.' : 'Zu Favoriten hinzugefügt.')
                  : 'Aus Favoriten entfernt.'),
            ));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
              child: Icon(
                fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(fav),
                size: 18,
                color: fav ? p.category(Category.sonstiges) : p.inkSoft,
              ),
            ),
            const SizedBox(width: 6),
            Text(fav ? 'Gemerkt' : 'Merken',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: fav ? p.category(Category.sonstiges) : p.inkSoft)),
          ]),
        ),
      ),
    );
  }
}
