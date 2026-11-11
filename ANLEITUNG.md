# Offene Türen – Anleitung

Die App zeigt Tage der offenen Tür in ganz Deutschland – nur solche, zu denen du mit 14 hindarfst.
Sie besteht aus zwei Teilen:

| Teil | Ordner | Was er macht |
|---|---|---|
| **App** (Flutter) | `app/` | Karte, Kalender, Favoriten. Lädt `events.json` und speichert sie offline. |
| **Sammel-Skript** (Python) | `crawler/` | Sucht Termine auf öffentlichen Websites und schreibt `data/events.json`. Läuft täglich kostenlos über GitHub Actions. |

---

## 1. APK aufs Handy bringen und installieren

Die fertige APK liegt hier: **`C:\Users\erika\OffeneTueren-arm64.apk`** (ca. 19 MB).

1. **APK aufs Handy kopieren** – z. B. per USB-Kabel in den Ordner *Download*, per Google Drive
   oder per Mail an dich selbst.
2. Auf dem Handy die App **„Eigene Dateien“** (Samsung) öffnen → *Downloads* → **OffeneTueren-arm64.apk** antippen.
3. Android fragt: *„Aus Sicherheitsgründen ist die Installation unbekannter Apps aus dieser Quelle nicht erlaubt.“*
   - Tippe auf **Einstellungen**.
   - Schalte **„Berechtigung zulassen“** (bzw. *„Unbekannte Apps installieren“*) für „Eigene Dateien“ **ein**.
   - Mit dem Zurück-Pfeil zurückgehen.
4. Auf **Installieren** tippen. Falls Google Play Protect warnt („App wurde nicht geprüft“):
   **Weitere Details → Trotzdem installieren**. Das ist normal bei Apps, die nicht aus dem Play Store kommen.
5. Fertig – „Offene Türen“ erscheint bei deinen Apps (Symbol: geöffnete Tür).
6. **Sicherheit:** Danach kannst du die Erlaubnis aus Schritt 3 wieder ausschalten
   (*Einstellungen → Apps → ⋮ → Spezieller Zugriff → Unbekannte Apps installieren → Eigene Dateien → aus*).

Beim ersten Benutzen fragt die App:
- **Standort** (wenn du auf den Standort-Knopf tippst) – für „Zu meinem Standort“, Suchradius und Sortierung nach Entfernung.
- **Mitteilungen** (wenn du den ersten Termin merkst) – für die Erinnerung am Vortag um 18 Uhr.

---

## 2. Termine automatisch jeden Tag aktualisieren (GitHub)

Ohne diesen Schritt zeigt die App die Termine, die beim Bauen mitgeliefert wurden (aktuell 37 echte Termine).
Damit jeden Tag neue dazukommen:

1. Kostenloses Konto auf **github.com** anlegen (falls noch nicht vorhanden).
2. Neues Repository erstellen: **New repository** → Name z. B. `offene-tueren` → **Public** → *Create*.
   (Public, damit die App die Datei ohne Passwort laden kann. Es stehen nur öffentliche Termine drin.)
3. Den Ordner `C:\Users\erika\OffeneTueren` hochladen. Im Ordner ist schon ein Git-Projekt angelegt:
   ```bash
   git remote add origin https://github.com/DEIN-NAME/offene-tueren.git
   ```
   ```bash
   git push -u origin main
   ```
4. Auf GitHub: **Settings → Actions → General → Workflow permissions → „Read and write permissions“** → *Save*.
5. **Actions**-Reiter → „Termine aktualisieren“ → **Run workflow** (einmal von Hand starten zum Testen).
   Danach läuft es jeden Morgen um ca. 5 Uhr von selbst.
6. Die Adresse deiner Termine-Datei lautet dann:
   `https://raw.githubusercontent.com/DEIN-NAME/offene-tueren/main/data/events.json`
7. In der App: **Gemerkt → Einstellungen → Termine → Quelle** → diese Adresse eintragen → *Speichern*.
   (Oder die APK gleich mit der Adresse bauen, siehe Abschnitt 4.)

### Optional: KI-Auswertung mit Claude
Ohne KI liest das Skript strukturierte Daten (schema.org, iCal) und erkennt Termine in Terminlisten
und PDFs mit einfachen Regeln. **Mit** einem Claude-API-Schlüssel liest eine KI jede Seite genauer
und es gibt zusätzlich eine tägliche Websuche („Tag der offenen Tür“ + Stadt/Monat).

- Den Schlüssel gibt es unter console.anthropic.com – **dafür muss ein Erwachsener das Konto anlegen**
  (die API ist erst ab 18 und kostet Geld; dein Claude-Abo gilt dafür nicht).
- Im Repository: **Settings → Secrets and variables → Actions → New repository secret**,
  Name `ANTHROPIC_API_KEY`, Wert = Schlüssel.
- Kosten steuern in `.github/workflows/update-events.yml`: `LLM_MODEL` (z. B. `claude-haiku-5-5`
  ist sehr viel günstiger als das voreingestellte `claude-opus-5-5`), `MAX_LLM_PAGES`, `SEARCH_QUERIES`.

### Quellen erweitern
Weitere Seiten trägst du in `crawler/sources.yaml` ein (städtische Terminlisten, Hochschul-Seiten,
Messe-Seiten, iCal-Kalender, PDFs). Das Skript beachtet **robots.txt** automatisch und ruft jede Website
höchstens alle 2 Sekunden auf (oder langsamer, wenn die Seite das verlangt). Soziale Netzwerke und
Ticketportale stehen auf einer Sperrliste.

Lokal testen:
```bash
.venv\Scripts\python.exe crawler\crawl.py --no-llm
```
```bash
.venv\Scripts\python.exe crawler\summary.py data\events.json
```

---

## 3. Wie die Altersregel funktioniert

- Veranstaltungen **nur für Fachpublikum**, geladene Gäste oder Mitarbeitende werden schon vom Skript aussortiert.
- Termine mit **Mindestalter** (z. B. „ab 16 Jahren“, „nur für Volljährige“) werden in der App ausgeblendet,
  solange dein Alter darunter liegt (*Einstellungen → Mein Alter*, steht auf 14).
- **Bundeswehr**-Termine kommen nur rein, wenn sie ausdrücklich öffentlich/für Familien sind oder ab 14 erlaubt.
- Steht „nur in Begleitung eines Erwachsenen“ dabei, zeigt die App einen gelben Hinweis **„Begleitung nötig“**.

Wichtig: Alles wird automatisch gefunden. Schau vor dem Hingehen kurz auf die Website des Termins.

---

## 4. APK selbst neu bauen

Voraussetzungen sind auf diesem PC schon installiert (Flutter in `C:\Users\erika\flutter`, Android-SDK, Java 21).

```powershell
cd C:\Users\erika\OffeneTueren
.\build-apk.ps1
```
Mit fester Termine-Adresse und neuer Versionsnummer (für Updates über die installierte App):
```powershell
.\build-apk.ps1 -EventsUrl "https://raw.githubusercontent.com/DEIN-NAME/offene-tueren/main/data/events.json" -Version "1.1.0+2"
```

**Signierschlüssel:** `C:\Users\erika\OffeneTuerenKeys\` (bewusst *außerhalb* von OneDrive und nicht im Git).
Nicht löschen und am besten sichern – ohne diesen Schlüssel lassen sich keine Updates über die
installierte App spielen (man müsste sie dann erst deinstallieren, und gemerkte Termine wären weg).

---

## Technik in Kürze

- Flutter 3.47 / Dart 3.13, Material 3, Pakete: flutter_map, geolocator, table_calendar, http,
  flutter_local_notifications, add_2_calendar (+ shared_preferences, url_launcher, path_provider, timezone, intl).
- Karte: OpenStreetMap-Kacheln (ohne API-Schlüssel), farblich gedämpft bzw. im Dunkelmodus umgekehrt.
  Pins werden beim Rauszoomen zu Gruppen zusammengefasst; der farbige Ring zeigt die Kategorien darin.
- Termine, die gerade laufen, haben einen ruhig pulsierenden Ring.
- Animationen werden abgeschaltet, wenn Android „Animationen entfernen“ aktiv ist.
