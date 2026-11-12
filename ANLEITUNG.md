# Was geht? (früher „Offene Türen“) – Anleitung

Die App zeigt dir in drei Bereichen, was in deiner Nähe los ist – nur Angebote, die mit deinem Alter erlaubt sind:

| Bereich | Datei | Woher die Daten kommen |
|---|---|---|
| **Tag der offenen Tür** (Schulen, Unis, Firmen, Behörden) | `data/events.json` | städtische Terminlisten, Hochschul- und Messeseiten, **alle Schulen/Hochschulen/Feuerwachen im Umkreis von Meerbusch** (aus OpenStreetMap) |
| **Freizeit & Events** (Gratis-Events, Flohmärkte, Ferienprogramme, Saisonales) | `data/freizeit.json` | Stadtkalender Meerbusch, Neuss, Krefeld, visitduesseldorf.de, Jugendzentren/Museen/Eisbahnen im Umkreis |
| **Ferienjobs** | `data/jobs.json` | Jobsuche der Bundesagentur für Arbeit, eingestuft nach dem Jugendarbeitsschutzgesetz |

Ein Python-Skript sammelt das jeden Morgen automatisch über GitHub Actions:
**https://github.com/FishYorkCity67/offene-tueren** (Reiter „Actions“ → „Termine aktualisieren“).
Die App lädt die Dateien beim Start und speichert sie für unterwegs (offline).

---

## 1. Neue APK installieren (Update)

Datei: **`C:\Users\erika\OffeneTueren-arm64.apk`** (ca. 20 MB, Version 2.0.0)

1. APK aufs Handy kopieren (USB-Kabel → Ordner *Download*, Google Drive oder Mail an dich selbst).
2. In **„Eigene Dateien“** → *Downloads* → **OffeneTueren-arm64.apk** antippen.
3. Falls Android fragt: **Einstellungen** → „Berechtigung zulassen“ (*Unbekannte Apps installieren*) **einschalten** → zurück.
4. **Aktualisieren** bzw. **Installieren** tippen. Warnt Play Protect: *Weitere Details → Trotzdem installieren*.
5. Fertig. Die App heißt jetzt **„Was geht?“** – deine gemerkten Termine bleiben erhalten.
6. Danach die Erlaubnis aus Schritt 3 am besten wieder ausschalten.

Beim ersten Benutzen fragt die App nach **Standort** (für „in deiner Nähe“) und **Mitteilungen**
(Erinnerung am Vortag und „Neue Ferienjobs in 10 km Umkreis“).

---

## 2. Was ist neu in 2.0

- **Untere Leiste:** Karte | Kalender | Ferienjobs | Favoriten
- **Karte & Kalender:** oben umschaltbar „Tag der offenen Tür“ / „Freizeit & Events“, darunter die
  Unterkategorien (eigene Farbe + Symbol) und **„Nur kostenlos“**.
- **Kalender:** Mehrtägiges (z. B. Weihnachtsmarkt) als **durchgehender Balken**, eintägige Termine als Punkte.
- **„Gerade offen“** bei Weihnachtsmärkten & Co. mit täglichen Öffnungszeiten.
- **Ferienjobs:** Liste oder Karte, Filter für Entfernung, Art, Zeitraum (Weihnachts-/Oster-/Sommer-/Herbstferien)
  und Bezahlung, Hinweis „Sprich vor einer Bewerbung mit deinen Eltern.“ und **„Was darf ich?“** mit Link zum
  Bundesarbeitsministerium. Jeder Job ist eingestuft: **ab 13/14 möglich, ab 15, ab 16, ab 18** – du siehst nur,
  was zu deinem Alter passt. Anzeigen ohne Arbeitgeber oder mit Vorkasse, „schnell reich“, Krypto,
  Paketagent oder nur Chat-Kontakt werden verworfen.
- **Einstellungen:** Alter, welche Kategorien du sehen willst, Mitteilungen pro Bereich
  (neue Tage der offenen Tür / Freizeit-Events / Ferienjobs im Umkreis von 5–50 km).
  Geprüft wird beim Öffnen der App und etwa alle 6 Stunden im Hintergrund.

**Ehrlich gesagt:** Bei der Arbeitsagentur gibt es rund um Meerbusch gerade fast keine Jobs „ab 13/14“
(solche Jobs laufen meist über Nachbarn und Aushänge). Für 14 Jahre ist die Liste deshalb oft leer –
die App sagt dir dann, wie viele Jobs erst ab 15/16/18 erlaubt sind, und gibt Tipps.

---

## 3. Welche Dateien geändert wurden

**Sammel-Skript (`crawler/`)**
- `crawler/feeds/offene-tueren.yaml`, `freizeit.yaml`, `jobs.yaml` – **neu: eine Konfiguration pro Kategorie**
  (Stichwörter, Unterkategorien, Regeln, Quellen, Umkreis-Modus, Websuche, Sperrliste). Ersetzt `sources.yaml`.
- `crawler/crawl.py` – liest alle Feed-Dateien, Umkreis-Modus über OpenStreetMap, Preise/„Eintritt frei“,
  Öffnungszeiten, mehrwöchige Zeiträume, Aussteller-Aufrufe werden aussortiert.
- `crawler/jobs.py` – **neu:** Jobsuche der Arbeitsagentur, Einstufung nach Jugendarbeitsschutz, Betrugs-Filter.
- `.github/workflows/update-events.yml` – erzeugt jetzt alle drei Dateien.

**App (`app/lib/`)**
- `models/event.dart` (Bereiche + 8 Kategorien), `models/job.dart` (neu)
- `data/feeds.dart` (neu: Laden/Offline-Speicher für 3 Dateien), `config.dart` (neu: Name, Datenadresse, BMAS-Link)
- `state/app_state.dart` (Filter, Jobs, Einstellungen, Mitteilungen)
- `services/watch.dart` (neu: „neue Einträge in deiner Nähe“, Hintergrund-Prüfung), `services/notifications.dart`
- `ui/filter_card.dart` (neu), `ui/jobs_screen.dart` (neu), `ui/job_sheet.dart` (neu, inkl. „Was darf ich?“),
  `ui/map_screen.dart`, `ui/calendar_screen.dart` (Balken), `ui/event_sheet.dart`, `ui/favorites_screen.dart`,
  `ui/home.dart` (4 Tabs), `ui/widgets.dart`, `ui/format.dart`, `theme.dart` (Farben), `main.dart`
- `app/assets/app_name.txt` (neu), `app/pubspec.yaml` (Version 2.0.0, Paket `workmanager`),
  `app/android/app/build.gradle.kts` + `AndroidManifest.xml` (App-Name aus der Datei)

---

## 4. Eine neue Kategorie hinzufügen

1. `crawler/feeds/freizeit.yaml` kopieren, z. B. nach `crawler/feeds/sport.yaml`.
2. `title`, `output: sport.json`, `keywords`, `categories`, `rules`, `sources` anpassen.
3. Hochladen – ab dem nächsten Morgen entsteht `data/sport.json`.
   (Damit die **App** sie anzeigt, muss sie noch in `app/lib/models/event.dart` als `Area` eingetragen werden.)

## 5. App-Name ändern

`app/assets/app_name.txt` öffnen, z. B. `Offene Türen` hineinschreiben, speichern, APK neu bauen.

## 6. APK selbst neu bauen

```powershell
cd C:\Users\erika\OffeneTueren
.\build-apk.ps1 -Version "2.0.1+3"
```
Die Zahl nach dem **+** bei jedem Update erhöhen. **Signierschlüssel:** `C:\Users\erika\OffeneTuerenKeys\` –
nicht löschen und am besten sichern, sonst gehen keine Updates über die installierte App.

## 7. KI-Auswertung (optional)

Mit einem Claude-API-Schlüssel (Repository → *Settings → Secrets and variables → Actions* →
`ANTHROPIC_API_KEY`) liest eine KI die Seiten genauer, sucht zusätzlich im Web und stuft Jobs genauer ein
(sie darf Jobs nur **strenger** einstufen als die festen Regeln). Das Konto muss ein Erwachsener anlegen;
die Nutzung kostet Geld (`LLM_MODEL: claude-haiku-5-5` in der Workflow-Datei ist deutlich günstiger).
Ohne Schlüssel funktioniert alles, die Freizeit-Titel sind dann aber manchmal etwas holprig.

## Hinweise zu den Quellen

- robots.txt wird immer beachtet, jede Website höchstens alle 2 Sekunden abgerufen.
- **Nicht** genutzt, weil die Nutzungsbedingungen das automatische Übernehmen verbieten: meinestadt.de,
  festivalsindeutschland.de. duesseldorf.de sperrt Crawler per robots.txt.
- Gespeichert werden nur Fakten (Datum, Ort, Titel, kurze Beschreibung) mit Link zur Quelle.
- Karte: © OpenStreetMap-Mitwirkende. Jobs: Jobbörse der Bundesagentur für Arbeit.
