import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/event.dart';
import '../models/job.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'format.dart';

Future<void> showJobSheet(BuildContext context, Job job) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => JobSheet(job: job),
  );
}

Future<void> showJobRules(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const JobRulesSheet(),
  );
}

Future<void> _open(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link konnte nicht geöffnet werden.')));
  }
}

/// Kapsel mit der Altersstufe ("ab 13/14 möglich", "ab 15" …).
class AgeBadge extends StatelessWidget {
  const AgeBadge(this.minAge, {super.key});
  final int minAge;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.ageColor(minAge);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: p.dark ? 0.2 : 0.11), borderRadius: BorderRadius.circular(99)),
      child: Text(ageClassLabel(minAge), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// Hinweis "Sprich vor einer Bewerbung mit deinen Eltern."
class ParentsBanner extends StatelessWidget {
  const ParentsBanner({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.fromLTRB(14, compact ? 10 : 12, 8, compact ? 10 : 12),
      decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Icon(Icons.family_restroom_rounded, color: p.warn, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Sprich vor einer Bewerbung mit deinen Eltern.',
              style: t.bodyMedium?.copyWith(color: p.warn, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => showJobRules(context),
          style: TextButton.styleFrom(foregroundColor: p.warn),
          child: const Text('Was darf ich?'),
        ),
      ]),
    );
  }
}

class JobSheet extends StatelessWidget {
  const JobSheet({super.key, required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final j = job;
    final km = s.distanceKm(j.point);
    final fav = s.isFavoriteId(j.id);
    final place = [if (j.address.isNotEmpty) j.address else j.city].join();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + MediaQuery.paddingOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _TypeBadge(j.type, size: 30),
            const SizedBox(width: 10),
            Flexible(child: Text(j.type.label, style: t.labelLarge?.copyWith(color: p.accent))),
            const SizedBox(width: 10),
            AgeBadge(j.minAge),
            const Spacer(),
            IconButton(
              tooltip: fav ? 'Gemerkt' : 'Merken',
              onPressed: () => s.toggleFavoriteId(j.id, remind: false),
              icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: fav ? p.category(Category.sonstiges) : p.inkSoft),
            ),
          ]),
          const SizedBox(height: 12),
          Text(j.title, style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(j.employer, style: t.bodyLarge?.copyWith(color: p.muted)),
          const SizedBox(height: 18),
          _Row(icon: Icons.verified_user_outlined, title: ageClassLabel(j.minAge), subtitle: j.ageReason),
          if (place.isNotEmpty || km != null)
            _Row(icon: Icons.place_outlined, title: place.isEmpty ? 'Ort siehe Anzeige' : place,
                subtitle: km != null ? '${distance(km)} von dir entfernt' : null),
          if (j.hours.isNotEmpty) _Row(icon: Icons.schedule_rounded, title: j.hours, subtitle: 'Arbeitszeit laut Anzeige'),
          _Row(icon: Icons.euro_rounded, title: j.pay.isEmpty ? 'Bezahlung nicht angegeben' : j.pay,
              subtitle: j.pay.isEmpty
                  ? 'Frag vorher nach dem Lohn – der gesetzliche Mindestlohn gilt für Jugendliche unter 18 ohne Berufsabschluss nicht.'
                  : null),
          _Row(icon: Icons.date_range_rounded, title: j.period,
              subtitle: j.start != null ? 'Beginn ab ${j.start!.day}.${j.start!.month}.${j.start!.year}' : null),
          if (j.contact.isNotEmpty) _Row(icon: Icons.contact_mail_outlined, title: 'Kontakt', subtitle: j.contact),
          if (j.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(j.description, style: t.bodyMedium),
          ],
          const SizedBox(height: 16),
          _RulesReminder(minAge: j.minAge),
          const SizedBox(height: 16),
          const ParentsBanner(compact: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: j.url.isEmpty ? null : () => _open(context, j.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              label: const Text('Anzeige öffnen'),
            ),
          ),
          if (j.point != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _open(context,
                    'https://www.google.com/maps/dir/?api=1&destination=${j.point!.latitude},${j.point!.longitude}&travelmode=transit'),
                icon: const Icon(Icons.directions_rounded, size: 19),
                label: const Text('Weg dorthin'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text('Quelle: ${j.source.isEmpty ? 'Jobbörse' : j.source}. Automatisch eingestuft – prüfe die Anzeige genau.',
              style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _RulesReminder extends StatelessWidget {
  const _RulesReminder({required this.minAge});
  final int minAge;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final text = switch (minAge) {
      <= 14 => 'Mit 13–14: nur leichte Arbeit, höchstens 2 Stunden am Tag, nur zwischen 8 und 18 Uhr, '
          'nicht vor oder während der Schule – und nur mit Einverständnis deiner Eltern.',
      15 => 'Ab 15 (noch schulpflichtig): Ferienjobs höchstens 4 Wochen im Jahr, '
          'max. 8 Stunden am Tag und 40 Stunden in der Woche, zwischen 6 und 20 Uhr.',
      _ => 'Für Jugendliche gilt: max. 8 Stunden am Tag, 40 in der Woche, Pausen ab 4,5 Stunden Arbeit.',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.gavel_rounded, size: 20, color: p.inkSoft),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: t.bodyMedium)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle});
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
              if (subtitle != null && subtitle!.isNotEmpty) ...[
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

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.type, {super.key, this.size = 44});
  final JobType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: p.dark ? 0.2 : 0.11),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(type.icon, size: size * 0.5, color: p.accent),
    );
  }
}

/// Öffentliche Variante für Listen.
class JobTypeBadge extends _TypeBadge {
  const JobTypeBadge(super.type, {super.key, super.size});
}

/// "Was darf ich?" – die wichtigsten Regeln des Jugendarbeitsschutzgesetzes, kurz erklärt.
class JobRulesSheet extends StatelessWidget {
  const JobRulesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    Widget section(String title, Color color, List<String> points) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.outline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium?.copyWith(color: color)),
            const SizedBox(height: 8),
            for (final pt in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(pt, style: t.bodyMedium)),
                ]),
              ),
          ]),
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Was darf ich?', style: t.headlineSmall),
          const SizedBox(height: 6),
          Text('Die wichtigsten Regeln aus dem Jugendarbeitsschutzgesetz – kurz erklärt.', style: t.bodyMedium),
          const SizedBox(height: 16),
          section('Unter 13', p.muted, const [
            'Arbeiten ist grundsätzlich nicht erlaubt.',
          ]),
          section('Mit 13 und 14', p.ageColor(13), const [
            'Nur leichte Arbeit, die für Kinder geeignet ist – z. B. Zeitungen oder Prospekte austragen, '
                'Nachhilfe geben, Babysitten, Gartenarbeit, Hunde ausführen, Einkaufshilfe.',
            'Nur mit Einverständnis deiner Eltern.',
            'Höchstens 2 Stunden am Tag.',
            'Nur zwischen 8 und 18 Uhr – nicht vor der Schule und nicht während des Unterrichts.',
          ]),
          section('Ab 15 (wenn du noch zur Schule gehst)', p.ageColor(15), const [
            'In den Ferien: Ferienjob höchstens 4 Wochen im Kalenderjahr.',
            'Höchstens 8 Stunden am Tag und 40 Stunden in der Woche, an 5 Tagen.',
            'Arbeiten nur zwischen 6 und 20 Uhr (einige Ausnahmen ab 16, z. B. Gastronomie).',
            'Pausen: 30 Minuten ab 4,5 Stunden Arbeit, 60 Minuten ab mehr als 6 Stunden.',
          ]),
          section('Immer', p.accent, const [
            'Keine gefährlichen Arbeiten, keine Akkord- oder Fließbandarbeit.',
            'Kein Geld vorab zahlen, keine Pakete oder Geld für Fremde weiterleiten.',
            'Seriöse Arbeitgeber nennen ihren Namen und eine Adresse – nicht nur einen Chat.',
          ]),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _open(context, kBmasJugendarbeitsschutzUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Offizielle Infos (Bundesarbeitsministerium)'),
            ),
          ),
          const SizedBox(height: 10),
          Text('Kurzfassung ohne Gewähr. Verbindlich ist das Jugendarbeitsschutzgesetz.', style: t.bodySmall),
        ]),
      ),
    );
  }
}
