import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/job.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'format.dart';
import 'job_sheet.dart';
import 'map_screen.dart' show buildTileLayer;
import 'widgets.dart';

enum _View { list, map }

/// Ferienjobs: Liste oder Karte, nur Jobs, die für mein Alter erlaubt sein können.
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, required this.bottomInset});
  final double bottomInset;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  _View _view = _View.list;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final jobs = s.filteredJobs;
    final top = MediaQuery.paddingOf(context).top;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(16, top + 18, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text('Ferienjobs', style: t.headlineMedium)),
            if (s.refreshing)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.muted)),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '${jobs.length} ${jobs.length == 1 ? 'passender Job' : 'passende Jobs'} für ${s.age} Jahre'
            '${s.jobRadiusKm != null ? ' · ${s.jobRadiusKm} km Umkreis' : ''}',
            style: t.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        const ParentsBanner(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: SegmentPill<_View>(
              values: _View.values,
              selected: _view,
              label: (v) => v == _View.list ? 'Liste' : 'Karte',
              onChanged: (v) => setState(() => _view = v),
            ),
          ),
          const SizedBox(width: 10),
          _FilterButton(active: s.jobFiltersActive, onTap: () => _showFilters(context)),
        ]),
        if (s.jobTypes.isNotEmpty || s.jobPeriod != JobPeriod.all || s.jobPay != JobPay.all) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final ty in s.jobTypes) InfoTag(ty.label, color: p.accent, icon: ty.icon),
            if (s.jobPeriod != JobPeriod.all) InfoTag(s.jobPeriod.label, color: p.accent),
            if (s.jobPay != JobPay.all) InfoTag(s.jobPay.label, color: p.accent),
          ]),
        ],
      ]),
    );

    if (_view == _View.map) {
      return Column(children: [
        header,
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, widget.bottomInset + 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _JobMap(jobs: jobs),
            ),
          ),
        ),
      ]);
    }

    return ListView(
      padding: EdgeInsets.only(bottom: widget.bottomInset + 24),
      children: [
        header,
        const SizedBox(height: 14),
        if (jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _NoJobs(tooYoung: s.jobsTooYoung, total: s.jobCount, filtersActive: s.jobFiltersActive),
          )
        else
          for (final (i, j) in jobs.indexed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Appear(key: ValueKey('job${j.id}'), index: i, child: JobTile(job: j)),
            ),
        if (jobs.isNotEmpty && s.jobsTooYoung > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Text('${s.jobsTooYoung} weitere Jobs sind erst ab einem höheren Alter erlaubt und ausgeblendet.',
                style: t.bodySmall),
          ),
      ],
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => AppScope(state: AppScope.read(context), child: const _JobFilterSheet()),
    );
  }
}

class JobTile extends StatelessWidget {
  const JobTile({super.key, required this.job, this.trailing});
  final Job job;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final km = s.distanceKm(job.point);
    final meta = [job.employer, if (job.city.isNotEmpty) job.city, if (km != null) distance(km)].join(' · ');
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showJobSheet(context, job),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: p.outline)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            JobTypeBadge(job.type),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                const SizedBox(height: 4),
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  AgeBadge(job.minAge),
                  if (job.period != 'Nebenbei') InfoTag(job.period, color: p.accent),
                  if (job.pay.isNotEmpty) InfoTag(job.pay),
                  if (job.hours.isNotEmpty) InfoTag(job.hours),
                ]),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: active ? p.ink : p.surface,
      shape: StadiumBorder(side: BorderSide(color: active ? p.ink : p.outline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune_rounded, size: 18, color: active ? p.onInk : p.inkSoft),
            const SizedBox(width: 6),
            Text('Filter',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: active ? p.onInk : p.inkSoft)),
          ]),
        ),
      ),
    );
  }
}

class _NoJobs extends StatelessWidget {
  const _NoJobs({required this.tooYoung, required this.total, required this.filtersActive});
  final int tooYoung;
  final int total;
  final bool filtersActive;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: p.outline)),
      child: Column(children: [
        EmptyState(
          icon: Icons.work_off_outlined,
          title: 'Gerade nichts Passendes',
          text: total == 0
              ? 'Die Jobliste wurde noch nicht geladen.'
              : tooYoung > 0
                  ? 'Von $total Jobs in der Nähe sind $tooYoung erst ab einem höheren Alter erlaubt.'
                  : 'Mit diesen Filtern gibt es gerade keine Jobs.',
          action: filtersActive
              ? OutlinedButton(onPressed: s.resetJobFilters, child: const Text('Filter zurücksetzen'))
              : null,
        ),
        if (s.age <= 14)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(16)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline_rounded, color: p.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Jobs für 13- und 14-Jährige stehen selten in Jobbörsen. Typisch sind Babysitten, Nachhilfe, '
                    'Hunde ausführen, Gartenhilfe oder Prospekte austragen – frag in der Nachbarschaft, '
                    'schau nach Aushängen im Supermarkt oder bei der Lokalzeitung.',
                    style: t.bodyMedium,
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _JobMap extends StatelessWidget {
  const _JobMap({required this.jobs});
  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final pts = jobs.where((j) => j.point != null).toList();
    final center = s.myLocation ?? (pts.isNotEmpty ? pts.first.point! : const LatLng(51.2556, 6.6933));
    return ColoredBox(
      color: p.dark ? const Color(0xFF1B1B1D) : const Color(0xFFF2F0EB),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 10.5,
          minZoom: 5,
          maxZoom: 18,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          buildTileLayer(calm: s.calmMap, dark: p.dark),
          if (s.myLocation != null)
            MarkerLayer(markers: [
              Marker(
                point: s.myLocation!,
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.surface, width: 3),
                  ),
                ),
              ),
            ]),
          MarkerLayer(markers: [
            for (final j in pts)
              Marker(
                point: j.point!,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => showJobSheet(context, j),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.ageColor(j.minAge),
                      shape: BoxShape.circle,
                      border: Border.all(color: p.surface, width: 2.5),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Icon(j.type.icon, size: 18, color: Colors.white),
                  ),
                ),
              ),
          ]),
          const SimpleAttributionWidget(source: Text('OpenStreetMap-Mitwirkende')),
        ],
      ),
    );
  }
}

class _JobFilterSheet extends StatelessWidget {
  const _JobFilterSheet();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    Widget title(String x) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(x, style: t.titleMedium),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Jobs filtern', style: t.headlineSmall)),
            TextButton(onPressed: s.resetJobFilters, child: const Text('Zurücksetzen')),
          ]),
          title('Entfernung'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final km in const [5, 10, 25, 50])
              ChoicePill(label: '$km km', selected: s.jobRadiusKm == km, onTap: () => s.setJobFilters(radius: km)),
            ChoicePill(label: 'Egal', selected: s.jobRadiusKm == null, onTap: () => s.setJobFilters(clearRadius: true)),
          ]),
          if (s.myLocation == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Tipp: Erlaube den Standort, damit die Entfernung stimmt.', style: t.bodySmall),
            ),
          title('Art des Jobs'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final ty in JobType.values)
              ChoicePill(label: ty.label, icon: ty.icon, selected: s.jobTypes.contains(ty), onTap: () => s.toggleJobType(ty)),
          ]),
          title('Zeitraum'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final pr in JobPeriod.values)
              ChoicePill(label: pr.label, selected: s.jobPeriod == pr, onTap: () => s.setJobFilters(period: pr)),
          ]),
          title('Bezahlung'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final pay in JobPay.values)
              ChoicePill(label: pay.label, selected: s.jobPay == pay, onTap: () => s.setJobFilters(pay: pay)),
          ]),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('${s.filteredJobs.length} Jobs anzeigen'),
            ),
          ),
        ]),
      ),
    );
  }
}
