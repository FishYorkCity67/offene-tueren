import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/event.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'calendar_screen.dart';
import 'favorites_screen.dart';
import 'jobs_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _prev = 0;

  static const _barHeight = 60.0;

  void _go(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _prev = _tab;
      _tab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final barBottom = bottomPad + 12;
    final inset = barBottom + _barHeight;
    final favCount = s.favoriteEvents.length + s.favoriteJobs.length;

    final pages = [
      MapScreen(bottomInset: inset),
      CalendarScreen(bottomInset: inset),
      JobsScreen(bottomInset: inset),
      FavoritesScreen(bottomInset: inset),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _go(0);
        },
        child: Scaffold(
          body: Stack(children: [
            for (var i = 0; i < pages.length; i++)
              _TabPage(
                active: i == _tab,
                direction: i == _tab ? (_tab > _prev ? 1 : -1) : (i < _tab ? -1 : 1),
                // Kalender und Favoriten auf dem breiten Fold-Innendisplay nicht endlos breit ziehen
                child: i == 0
                    ? pages[i]
                    : Center(
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: pages[i]),
                      ),
              ),
            // Statusleiste über Kalender/Favoriten abdecken, damit Text nicht darunter läuft
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: MediaQuery.paddingOf(context).top,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _tab == 0 ? 0 : 1,
                  duration: Motion.of(context, Motion.fast),
                  child: ColoredBox(color: p.background.withValues(alpha: 0.96)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: barBottom,
              child: Center(
                child: _NavCapsule(
                  index: _tab,
                  onTap: _go,
                  height: _barHeight,
                  favCount: favCount,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Blendet Tabs weich ein und schiebt sie ein Stück in Wischrichtung.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.active, required this.direction, required this.child});
  final bool active;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.medium);
    final p = Palette.of(context);
    // Die Ein-/Ausblendung selbst muss laufen dürfen – angehalten werden nur die Animationen
    // INNERHALB eines verdeckten Tabs (z. B. pulsierende Pins).
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: d,
          curve: Motion.curve,
          child: AnimatedSlide(
            offset: active ? Offset.zero : Offset(0.04 * direction, 0),
            duration: d,
            curve: Motion.curve,
            child: TickerMode(
              enabled: active,
              child: ExcludeSemantics(
                excluding: !active,
                child: ColoredBox(color: p.background, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCapsule extends StatelessWidget {
  const _NavCapsule({required this.index, required this.onTap, required this.height, required this.favCount});
  final int index;
  final ValueChanged<int> onTap;
  final double height;
  final int favCount;

  static const _items = [
    (Icons.map_outlined, Icons.map_rounded, 'Karte'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Kalender'),
    (Icons.work_outline_rounded, Icons.work_rounded, 'Ferienjobs'),
    (Icons.favorite_border_rounded, Icons.favorite_rounded, 'Favoriten'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.outline),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.08), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _items.length; i++)
          _NavItem(
            icon: _items[i].$1,
            activeIcon: _items[i].$2,
            label: _items[i].$3,
            active: i == index,
            badge: i == 3 && favCount > 0 ? favCount : null,
            onTap: () => onTap(i),
          ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.active, required this.onTap, this.badge});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = Motion.of(context, Motion.medium);
    return Semantics(
      selected: active,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: d,
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: active ? 18 : 16),
          decoration: BoxDecoration(
            color: active ? p.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                child: Icon(active ? activeIcon : icon,
                    key: ValueKey(active), size: 22, color: active ? p.onInk : p.inkSoft),
              ),
              if (badge != null && !active)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: p.category(Category.sonstiges),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: p.surface, width: 1.5),
                    ),
                    child: Text('$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
            AnimatedSize(
              duration: d,
              curve: Curves.easeOutCubic,
              child: active
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(label,
                          maxLines: 1,
                          style: TextStyle(color: p.onInk, fontWeight: FontWeight.w600, fontSize: 14)),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}
