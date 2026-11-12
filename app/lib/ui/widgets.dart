import 'package:flutter/material.dart';

import '../models/event.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'format.dart';

/// Rundes Symbol in der Kategorie-Farbe.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.size = 44, this.filled = false});

  final Category category;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.category(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c : p.categoryTint(category),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(category.icon, size: size * 0.5, color: filled ? Colors.white : c),
    );
  }
}

/// Kleiner Hinweis „Jetzt“ mit ruhig pulsierendem Punkt.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.label = 'Jetzt'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: p.dark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(color: p.accent, size: 7),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// Punkt mit einem sich ausbreitenden Ring (kein Leuchten, nur ein dünner Kreis).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Transform.scale(
              scale: 1 + t * 1.6,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.color.withValues(alpha: (1 - t) * 0.7), width: 1.2),
                ),
              ),
            ),
            Container(decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]);
        },
      ),
    );
  }
}

/// Liste-Eintrag für einen Termin (Kalender, Favoriten).
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, required this.onTap, this.trailing, this.showDate = true});

  final OpenDayEvent event;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final now = DateTime.now();
    final km = s.distanceKm(event.point);
    final rel = relativeDay(event, now);
    final t = Theme.of(context).textTheme;
    final meta = [
      showDate ? dateAndTime(event) : timeRange(event),
      if (km != null) distance(km),
    ].join(' · ');
    final price = priceLabel(event);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.outline),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CategoryBadge(event.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(event.kind.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelMedium?.copyWith(
                            color: p.category(event.category), fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  ),
                  if (event.isLive(now)) ...[
                    const SizedBox(width: 8),
                    LiveBadge(label: event.daily ? 'Offen' : 'Jetzt'),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(event.headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                const SizedBox(height: 4),
                Text(meta, style: t.bodySmall),
                if (event.city.isNotEmpty || rel.isNotEmpty || event.needsAdult || price.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (rel.isNotEmpty && !event.isLive(now)) _Tag(rel, color: p.accent),
                    if (price.isNotEmpty)
                      _Tag(price, color: event.free == true ? p.category(Category.gratis) : null,
                          icon: event.free == true ? Icons.money_off_rounded : null),
                    if (event.city.isNotEmpty) _Tag(event.city),
                    if (event.needsAdult) _Tag('mit Begleitung', color: p.warn, icon: Icons.family_restroom_rounded),
                  ]),
                ],
              ]),
            ),
            if (trailing != null) trailing! else const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }
}

/// Kleines Etikett (öffentlich, damit es auch die Job-Ansicht nutzen kann).
class InfoTag extends _Tag {
  const InfoTag(super.text, {super.key, super.color, super.icon});
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color == null ? p.surfaceAlt : c.withValues(alpha: p.dark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Erscheint mit leichtem Hochgleiten; [index] staffelt den Start in Listen.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.medium);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 35 * widget.index.clamp(0, 10)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Motion.curve);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
        child: widget.child,
      ),
    );
  }
}

/// Schmale Kapsel mit gleitender Markierung – für die Zeitfilter.
class SegmentPill<T> extends StatelessWidget {
  const SegmentPill({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final idx = values.indexOf(selected);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.outline),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / values.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: Motion.of(context, Motion.medium),
            curve: Curves.easeOutBack,
            left: w * idx,
            width: w,
            top: 0,
            bottom: 0,
            child: Container(decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(99))),
          ),
          Row(children: [
            for (final v in values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(v),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: Motion.of(context, Motion.fast),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: v == selected ? p.onInk : p.inkSoft,
                      ),
                      child: Text(label(v), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Kategorie-Filter als Kapsel: aktiv = farbig gefüllt.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, required this.active, required this.onTap, this.onLongPress, this.count});

  final Category category;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.category(category);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        height: 36,
        padding: const EdgeInsets.only(left: 6, right: 12),
        decoration: BoxDecoration(
          color: active ? c : p.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? c : p.outline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white.withValues(alpha: 0.22) : p.categoryTint(category),
            ),
            child: Icon(category.icon, size: 15, color: active ? Colors.white : c),
          ),
          const SizedBox(width: 7),
          Text(category.short,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : p.inkSoft)),
          if (count != null) ...[
            const SizedBox(width: 5),
            Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white.withValues(alpha: 0.8) : p.muted)),
          ],
        ]),
      ),
    );
  }
}

/// Auswahl-Kapsel (z. B. "25 km", "Sommerferien"): gewählt = dunkel gefüllt.
class ChoicePill extends StatelessWidget {
  const ChoicePill({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.curve,
          padding: EdgeInsets.fromLTRB(icon != null ? 10 : 14, 8, 14, 8),
          decoration: BoxDecoration(
            color: selected ? p.ink : p.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? p.ink : p.outline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? p.onInk : p.inkSoft),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? p.onInk : p.inkSoft)),
          ]),
        ),
      ),
    );
  }
}

/// Leerer Zustand mit Symbol, Titel und Text.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle),
          child: Icon(icon, color: p.muted, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title, style: t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(text, style: t.bodyMedium?.copyWith(color: p.muted), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Kleine runde Schaltfläche (z. B. „Kalender“ in Listen).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.color, this.size = 40});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final btn = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: color ?? p.inkSoft)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
