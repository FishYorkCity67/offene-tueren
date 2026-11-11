import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'event_sheet.dart';
import 'widgets.dart';

// leicht nach Norden verschoben, weil oben die Filterkarte liegt
const _germanyCenter = LatLng(51.95, 10.45);
const _germanyZoom = 5.75;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.bottomInset});
  final double bottomInset;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  Tween<double>? _lat, _lng, _zoom;
  double _clusterZoom = _germanyZoom.floorToDouble();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_lat == null) return;
      final t = Curves.easeInOutCubic.transform(_anim.value);
      _map.move(LatLng(_lat!.transform(t), _lng!.transform(t)), _zoom!.transform(t));
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _flyTo(LatLng dest, double zoom) {
    if (!_mapReady) return;
    final cam = _map.camera;
    if (Motion.reduced(context)) {
      _map.move(dest, zoom);
      return;
    }
    _lat = Tween(begin: cam.center.latitude, end: dest.latitude);
    _lng = Tween(begin: cam.center.longitude, end: dest.longitude);
    _zoom = Tween(begin: cam.zoom, end: zoom);
    _anim.forward(from: 0);
  }

  void _fit(List<LatLng> pts) {
    if (!_mapReady || pts.isEmpty) return;
    final top = MediaQuery.paddingOf(context).top;
    final target = CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: EdgeInsets.fromLTRB(56, top + 200, 56, widget.bottomInset + 60),
      maxZoom: 16,
    ).fit(_map.camera);
    _flyTo(target.center, target.zoom);
  }

  Future<void> _locate() async {
    final s = AppScope.read(context);
    final pos = await s.locate();
    if (!mounted) return;
    if (pos != null) {
      final r = s.radiusKm;
      final zoom = r == null ? 10.5 : (r <= 10 ? 12.0 : r <= 25 ? 10.8 : r <= 50 ? 9.8 : 8.8);
      _flyTo(pos, zoom);
    } else {
      final msg = switch (s.locationStatus) {
        LocationStatus.off => 'Standort ist ausgeschaltet. Schalte ihn in den Schnelleinstellungen ein.',
        LocationStatus.denied => 'Ohne Standort-Erlaubnis kann ich dich nicht finden.',
        _ => 'Standort konnte nicht bestimmt werden.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _onCluster(_Cluster c) {
    if (c.events.length == 1) {
      showEventSheet(context, c.events.first);
      return;
    }
    final pts = c.events.map((e) => e.point!).toList();
    final spread = LatLngBounds.fromPoints(pts);
    final tiny = (spread.north - spread.south).abs() < 0.0008 && (spread.east - spread.west).abs() < 0.0008;
    if (tiny || _map.camera.zoom >= 15.5) {
      _showList(c.events);
    } else {
      _fit(pts);
    }
  }

  void _showList(List<OpenDayEvent> events) {
    final s = AppScope.read(context);
    final list = [...events]..sort((a, b) => a.start.compareTo(b.start));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text('${list.length} Termine an diesem Ort', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final (i, e) in list.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Appear(
                  index: i,
                  child: AppScope(state: s, child: EventTile(event: e, onTap: () => showEventSheet(ctx, e))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final events = s.mapEvents;
    final clusters = _cluster(events.where((e) => e.point != null).toList(), _clusterZoom);
    final now = DateTime.now();
    final top = MediaQuery.paddingOf(context).top;

    final filter = _tileFilter(calm: s.calmMap, dark: p.dark);

    return Stack(children: [
      Positioned.fill(
        child: ColoredBox(
          color: p.dark ? const Color(0xFF1B1B1D) : const Color(0xFFF2F0EB),
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _germanyCenter,
              initialZoom: _germanyZoom,
              minZoom: 4.8,
              maxZoom: 18,
              backgroundColor: Colors.transparent,
              cameraConstraint: CameraConstraint.containCenter(
                bounds: LatLngBounds(const LatLng(46.0, 3.5), const LatLng(56.2, 17.5)),
              ),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () => _mapReady = true,
              onPositionChanged: (cam, _) {
                final z = cam.zoom.floorToDouble();
                if (z != _clusterZoom) setState(() => _clusterZoom = z);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.offenetueren',
                maxNativeZoom: 19,
                tileBuilder: filter == null
                    ? null
                    : (context, tile, _) => ColorFiltered(colorFilter: filter, child: tile),
              ),
              if (s.myLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: s.myLocation!,
                    width: 26,
                    height: 26,
                    child: _MeDot(color: p.accent),
                  ),
                ]),
              MarkerLayer(
                markers: [
                  for (final c in clusters)
                    Marker(
                      key: ValueKey(c.key),
                      point: c.center,
                      width: c.events.length == 1 ? 46 : _clusterSize(c.events.length) + 14,
                      height: c.events.length == 1 ? 46 : _clusterSize(c.events.length) + 14,
                      child: _PopIn(
                        key: ValueKey('pop${c.key}'),
                        child: GestureDetector(
                          onTap: () => _onCluster(c),
                          child: c.events.length == 1
                              ? _Pin(event: c.events.first, live: c.events.first.isLive(now))
                              : _ClusterBubble(cluster: c, live: c.events.any((e) => e.isLive(now))),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),

      // ---- Filter oben -----------------------------------------------------------
      Positioned(
        left: 12,
        right: 12,
        top: top + 10,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _FilterCard(count: events.length),
          ),
        ),
      ),

      // ---- Hinweis, wenn nichts passt ---------------------------------------------
      if (!s.loading && events.isEmpty)
        Positioned(
          left: 24,
          right: 24,
          bottom: widget.bottomInset + 76,
          child: Appear(
            child: _FloatingNote(
              icon: Icons.search_off_rounded,
              text: s.allCount == 0
                  ? 'Noch keine Termine geladen. Prüfe die Datenquelle in den Einstellungen.'
                  : 'Keine Termine für diese Auswahl.',
              action: s.allCount == 0 || (s.timeFilter == TimeFilter.all && s.categories.length == 4)
                  ? null
                  : TextButton(
                      onPressed: () {
                        s.setTimeFilter(TimeFilter.all);
                        for (final c in Category.values) {
                          if (!s.categories.contains(c)) s.toggleCategory(c);
                        }
                      },
                      child: const Text('Alle zeigen'),
                    ),
            ),
          ),
        ),

      // ---- Standort-Knopf ------------------------------------------------------------
      Positioned(
        right: 16,
        bottom: widget.bottomInset + 14,
        child: _MapButton(
          icon: s.locationStatus == LocationStatus.searching
              ? null
              : (s.myLocation != null ? Icons.my_location_rounded : Icons.location_searching_rounded),
          onTap: _locate,
          tooltip: 'Zu meinem Standort',
        ),
      ),
      Positioned(
        right: 16,
        bottom: widget.bottomInset + 74,
        child: _MapButton(
          icon: Icons.zoom_out_map_rounded,
          onTap: () => _flyTo(_germanyCenter, _germanyZoom),
          tooltip: 'Ganz Deutschland',
          small: true,
        ),
      ),

      // ---- Quellenangabe (Pflicht bei OpenStreetMap) ------------------------------
      Positioned(
        left: 14,
        bottom: widget.bottomInset + 16,
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('© OpenStreetMap-Mitwirkende', style: TextStyle(fontSize: 10.5, color: p.muted)),
          ),
        ),
      ),
    ]);
  }
}

// =====================================================================================
// Kartenfarben: OpenStreetMap-Kacheln gedämpft (hell) bzw. umgekehrt (dunkel)
// =====================================================================================

/// Sättigungs-Matrix (Luminanz nach Rec. 709); s = 1 lässt Farben unverändert.
List<double> _saturate(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final i = 1 - s;
  return [
    lr * i + s, lg * i, lb * i, //
    lr * i, lg * i + s, lb * i, //
    lr * i, lg * i, lb * i + s, //
  ];
}

/// 3×3-Matrizen multiplizieren (Zeilen zuerst).
List<double> _mul(List<double> a, List<double> b) => [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
    ];

/// Farbton um 180° drehen: nach dem Umkehren wird Wasser so wieder blau statt braun.
const _hue180 = [-0.574, 1.43, 0.144, 0.426, 0.43, 0.144, 0.426, 1.43, -0.856];

ColorFilter? _tileFilter({required bool calm, required bool dark}) {
  if (!calm && !dark) return null;
  final sat = _saturate(calm ? 0.32 : 0.8);
  final m = dark ? _mul(sat, _hue180) : sat;
  // hell: 90 % Karte + 10 % Elfenbein; dunkel: umkehren und in warmes Anthrazit legen
  final scale = dark ? -0.72 : 0.9;
  final offs = dark ? [210.0, 209.0, 207.0] : [25.1, 25.0, 24.7];
  return ColorFilter.matrix([
    m[0] * scale, m[1] * scale, m[2] * scale, 0, offs[0], //
    m[3] * scale, m[4] * scale, m[5] * scale, 0, offs[1], //
    m[6] * scale, m[7] * scale, m[8] * scale, 0, offs[2], //
    0, 0, 0, 1, 0,
  ]);
}

// =====================================================================================
// Clustering: einfache Raster-Gruppierung in Bildschirm-Pixeln (Web-Mercator)
// =====================================================================================

class _Cluster {
  _Cluster(this.events, this.center, this.key);
  final List<OpenDayEvent> events;
  final LatLng center;
  final String key;
}

double _clusterSize(int n) => (34 + math.log(n) * 6).clamp(36, 58).toDouble();

List<_Cluster> _cluster(List<OpenDayEvent> events, double zoom) {
  const cell = 64.0; // Pixel
  final scale = 256 * math.pow(2, zoom);
  math.Point<double> project(LatLng p) {
    final x = (p.longitude + 180) / 360 * scale;
    final s = math.sin(p.latitude * math.pi / 180);
    final y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
    return math.Point(x, y);
  }

  // Ab Zoom 14 einzeln zeigen – außer Termine liegen fast exakt übereinander.
  final cellSize = zoom >= 14 ? 18.0 : cell;
  final buckets = <(int, int), List<(OpenDayEvent, math.Point<double>)>>{};
  for (final e in events) {
    final pt = project(e.point!);
    final k = ((pt.x / cellSize).floor(), (pt.y / cellSize).floor());
    (buckets[k] ??= []).add((e, pt));
  }
  // Nachbarzellen zusammenlegen, wenn ihre Mittelpunkte sehr nah beieinander liegen.
  final out = <_Cluster>[];
  final used = <(int, int)>{};
  final keys = buckets.keys.toList()..sort((a, b) => buckets[b]!.length.compareTo(buckets[a]!.length));
  for (final k in keys) {
    if (used.contains(k)) continue;
    used.add(k);
    final members = [...buckets[k]!];
    math.Point<double> mid() => math.Point(
        members.map((m) => m.$2.x).reduce((a, b) => a + b) / members.length,
        members.map((m) => m.$2.y).reduce((a, b) => a + b) / members.length);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final nk = (k.$1 + dx, k.$2 + dy);
        if (used.contains(nk) || !buckets.containsKey(nk)) continue;
        final other = buckets[nk]!;
        final om = math.Point(other.map((m) => m.$2.x).reduce((a, b) => a + b) / other.length,
            other.map((m) => m.$2.y).reduce((a, b) => a + b) / other.length);
        if (mid().distanceTo(om) < cellSize * 0.75) {
          members.addAll(other);
          used.add(nk);
        }
      }
    }
    final lat = members.map((m) => m.$1.point!.latitude).reduce((a, b) => a + b) / members.length;
    final lng = members.map((m) => m.$1.point!.longitude).reduce((a, b) => a + b) / members.length;
    final ids = members.map((m) => m.$1.id).toList()..sort();
    out.add(_Cluster(members.map((m) => m.$1).toList(), LatLng(lat, lng), ids.length == 1 ? ids.first : '${ids.first}+${ids.length}'));
  }
  return out;
}

// =====================================================================================
// Bausteine
// =====================================================================================

class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final counts = {for (final c in Category.values) c: 0};
    for (final e in s.relevant) {
      counts[e.category] = counts[e.category]! + 1;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.outline),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.3 : 0.06), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('Offene Türen', style: t.titleLarge),
          const SizedBox(width: 10),
          if (s.refreshing)
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.muted)),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: Text(
              count == 1 ? '1 Termin' : '$count Termine',
              key: ValueKey(count),
              style: t.labelLarge?.copyWith(color: p.muted),
            ),
          ),
        ]),
        if (s.fetchError != null && s.allCount > 0) ...[
          const SizedBox(height: 4),
          Text(s.fetchError!, style: t.bodySmall),
        ],
        const SizedBox(height: 10),
        SegmentPill<TimeFilter>(
          values: TimeFilter.values,
          selected: s.timeFilter,
          label: (f) => f == TimeFilter.month ? 'Monat' : f.label,
          onChanged: s.setTimeFilter,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: Category.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = Category.values[i];
              final allOn = s.categories.length == Category.values.length;
              return CategoryChip(
                category: c,
                active: s.categories.contains(c),
                count: counts[c],
                onTap: () => allOn ? s.onlyCategory(c) : s.toggleCategory(c),
                onLongPress: () => s.onlyCategory(c),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.event, required this.live});
  final OpenDayEvent event;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.category(event.category);
    final fav = AppScope.of(context).isFavorite(event);
    return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
      if (live) _PulseRing(color: c, size: 34),
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: p.surface, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(event.category.icon, size: 17, color: Colors.white),
      ),
      if (fav)
        Positioned(
          right: 1,
          top: 1,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
            child: Icon(Icons.favorite_rounded, size: 11, color: p.category(Category.sonstiges)),
          ),
        ),
    ]);
  }
}

class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.cluster, required this.live});
  final _Cluster cluster;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = cluster.events.length;
    final size = _clusterSize(n);
    final shares = {for (final c in Category.values) c: 0};
    for (final e in cluster.events) {
      shares[e.category] = shares[e.category]! + 1;
    }
    return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
      if (live) _PulseRing(color: p.accent, size: size),
      CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          shares: [for (final c in Category.values) if (shares[c]! > 0) (p.category(c), shares[c]! / n)],
          background: p.surface,
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Container(
              width: size - 12,
              height: size - 12,
              decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$n',
                  style: TextStyle(color: p.onInk, fontWeight: FontWeight.w700, fontSize: n > 99 ? 12 : 14)),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Dünner Ring um Gruppen: Anteile der Kategorien als farbige Bögen.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.shares, required this.background});
  final List<(Color, double)> shares;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    canvas.drawCircle(center, r, Paint()..color = background);
    final rect = Rect.fromCircle(center: center, radius: r - 3.2);
    var start = -math.pi / 2;
    final gap = shares.length > 1 ? 0.12 : 0.0;
    for (final (color, f) in shares) {
      final sweep = f * 2 * math.pi;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0.01, sweep - gap),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.shares != shares || old.background != background;
}

/// Ruhiger, sich ausbreitender Ring für Termine, die gerade laufen.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 0.4;
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
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Container(
            width: widget.size * (1 + 0.55 * t),
            height: widget.size * (1 + 0.55 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.16 * (1 - t)),
              border: Border.all(color: widget.color.withValues(alpha: 0.55 * (1 - t)), width: 2),
            ),
          );
        },
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Stack(alignment: Alignment.center, children: [
      _PulseRing(color: color, size: 18),
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: p.surface, width: 3),
        ),
      ),
    ]);
  }
}

/// Marker springen beim Erscheinen sanft auf.
class _PopIn extends StatelessWidget {
  const _PopIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 360)),
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Opacity(opacity: ((v - 0.4) / 0.6).clamp(0, 1), child: Transform.scale(scale: v, child: c)),
      child: child,
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap, required this.tooltip, this.small = false});
  final IconData? icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = small ? 44.0 : 52.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.surface,
        shape: CircleBorder(side: BorderSide(color: p.outline)),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: icon == null
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.ink))
                  : Icon(icon, size: small ? 20 : 23, color: p.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNote extends StatelessWidget {
  const _FloatingNote({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.outline),
      ),
      child: Row(children: [
        Icon(icon, color: p.muted, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ?action,
      ]),
    );
  }
}
