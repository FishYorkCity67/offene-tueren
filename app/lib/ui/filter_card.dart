import 'package:flutter/material.dart';

import '../config.dart';
import '../models/event.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// Filter oben auf Karte und Kalender:
///   Bereiche (Tag der offenen Tür / Freizeit & Events), Zeitraum (nur Karte),
///   Unterkategorien der gewählten Bereiche und "Nur kostenlos".
class FilterCard extends StatelessWidget {
  const FilterCard({super.key, required this.count, this.showTime = false, this.title});
  final int count;
  final bool showTime;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final counts = {for (final c in Category.values) c: 0};
    for (final e in s.relevant) {
      counts[e.category] = counts[e.category]! + 1;
    }
    final visibleAreas = Area.values.where((a) => a.categories.any(s.categoryVisible)).toList();
    final chips = Category.values.where((c) => s.areas.contains(c.area) && s.categoryVisible(c)).toList();
    final showFree = s.areas.contains(Area.freizeit) && visibleAreas.contains(Area.freizeit);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.outline),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.3 : 0.06), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Flexible(child: Text(title ?? AppConfig.appName, style: t.titleLarge, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          if (s.refreshing)
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.muted)),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: Text(
              count == 1 ? '1 Eintrag' : '$count Einträge',
              key: ValueKey(count),
              style: t.labelLarge?.copyWith(color: p.muted),
            ),
          ),
        ]),
        if (s.fetchError != null && s.allCount > 0) ...[
          const SizedBox(height: 4),
          Text(s.fetchError!, style: t.bodySmall),
        ],
        if (visibleAreas.length > 1) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final (i, a) in visibleAreas.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _AreaToggle(area: a, active: s.areas.contains(a), onTap: () => s.toggleArea(a))),
            ],
          ]),
        ],
        if (showTime) ...[
          const SizedBox(height: 10),
          SegmentPill<TimeFilter>(
            values: TimeFilter.values,
            selected: s.timeFilter,
            label: (f) => f == TimeFilter.month ? 'Monat' : f.label,
            onChanged: s.setTimeFilter,
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (showFree) ...[
                _FreeChip(active: s.onlyFree, onTap: () => s.setOnlyFree(!s.onlyFree)),
                const SizedBox(width: 8),
              ],
              for (final (i, c) in chips.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Builder(builder: (context) {
                  final areaAllOn = c.area.categories.every(s.categories.contains);
                  return CategoryChip(
                    category: c,
                    active: s.categories.contains(c),
                    count: counts[c],
                    // Sind alle Kategorien eines Bereichs an, wählt ein Tipp nur diese eine aus.
                    onTap: () => areaAllOn ? s.onlyCategory(c) : s.toggleCategory(c),
                    onLongPress: () => s.onlyCategory(c),
                  );
                }),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// Großer Umschalter für einen Bereich.
class _AreaToggle extends StatelessWidget {
  const _AreaToggle({required this.area, required this.active, required this.onTap});
  final Area area;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      toggled: active,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.curve,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? p.surfaceAlt : p.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: active ? p.ink : p.outline, width: active ? 1.4 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              child: Icon(active ? Icons.check_rounded : area.icon,
                  key: ValueKey(active), size: 17, color: active ? p.ink : p.muted),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(area.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? p.ink : p.muted)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FreeChip extends StatelessWidget {
  const _FreeChip({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.category(Category.gratis);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? c : p.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? c : p.outline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(active ? Icons.check_rounded : Icons.money_off_rounded, size: 16, color: active ? Colors.white : c),
          const SizedBox(width: 6),
          Text('Nur kostenlos',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : p.inkSoft)),
        ]),
      ),
    );
  }
}
