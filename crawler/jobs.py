"""Ferienjobs für Jugendliche – Quelle: Jobsuche der Bundesagentur für Arbeit.

Wird von crawl.py für Feed-Dateien mit `kind: jobs` aufgerufen (crawler/feeds/jobs.yaml).

Jeder Job wird nach dem Jugendarbeitsschutzgesetz (JArbSchG) eingestuft:
  13  "ab 13/14 möglich": nur leichte, geeignete Arbeit (Zeitungen/Prospekte austragen, Nachhilfe,
      Babysitten, Gartenarbeit, Hunde ausführen, Einkaufshilfe) mit Einverständnis der Eltern,
      max. 2 Std. am Tag, nur zwischen 8 und 18 Uhr, nicht vor/während der Schule.
  15  "ab 15": Ferienjob, max. 4 Wochen im Kalenderjahr, max. 8 Std./Tag und 40 Std./Woche.
  16  "ab 16"
  18  "ab 18": Nachtarbeit, sehr früher Arbeitsbeginn, Führerschein, Alkohol, Sicherheitsdienst …
Im Zweifel wird immer HÖHER eingestuft. Anzeigen ohne Arbeitgeber oder mit verdächtigen
Merkmalen (Vorkasse, "schnell reich werden", nur Chat-Kontakt …) werden verworfen.
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import re
import time
from typing import Any

import requests

import crawl as C

API = "https://rest.arbeitsagentur.de/jobboerse/jobsuche-service"
API_HEADERS = {"X-API-Key": "jobboerse-jobsuche"}   # öffentliche Client-ID der Jobbörse
JOB_LINK = "https://www.arbeitsagentur.de/jobsuche/jobdetail/{ref}"
API_DELAY = 0.6                                       # Sekunden zwischen zwei Anfragen

# ---- Art der Arbeit ---------------------------------------------------------------------
JOB_TYPES: list[tuple[str, str]] = [
    ("nachhilfe", r"nachhilfe|lernhilfe|hausaufgabenbetreuung|hausaufgabenhilfe"),
    ("babysitten", r"babysit|kinderbetreuung|kinderbetreuer|nanny|leihoma"),
    ("tiere", r"hund|gassi|tierbetreu|tiersitter|katzen|pferd|reitstall"),
    ("garten", r"garten|rasen|laub|grünpflege|gärtner"),
    ("einkauf", r"einkaufshilfe|einkäufe|einkaufsservice|senioren"),
    ("austragen", r"zeitung|prospekt|werbe(?:mittel|zettel|sendung|post|blätter)|flyer|zusteller|zustellung|"
                  r"austr[aä]g|verteil"),
    ("gastro", r"gastro|kellner|service ?kraft|servicemitarbeit|café|cafe|eisdiele|küche|imbiss|restaurant|spül|"
               r"bäckerei|theke|barista"),
    ("verkauf", r"verkauf|kasse|kassier|regal|einzelhandel|supermarkt|filiale|warenverräum"),
    ("lager", r"lager|kommission|logistik|produktion|verpack|montage|helfer"),
    ("buero", r"büro|empfang|telefon|verwaltung|rezeption|sekretariat"),
]
LIGHT_TYPES = {"austragen", "nachhilfe", "babysitten", "garten", "tiere", "einkauf"}

# ---- Signale für die Altersstufe --------------------------------------------------------
_ADULT = re.compile(
    r"ab 18|volljährig|mindestens 18|mind\. ?18|über 18|18 jahre|führerschein|fahrerlaubnis|klasse b\b|"
    r"\bpkw\b|\blkw\b|fahrer|nachtarbeit|nachtzustellung|nachtschicht|\bnachts\b|in der nacht|frühzustellung|"
    r"frühmorgens|vor 6|bis 6:00|ab [1-5][.:]00 uhr|ab [1-5] uhr|zwischen [1-5][.:]?0?0? und|"
    r"bis 2[2-4](?:[.:]00)? uhr|alkohol|\bbar\b|kneipe|nachtclub|spielhalle|casino|security|sicherheitsdienst|"
    r"bewachung|erwachsene bewerber|rentner|staplerschein|gabelstapler|schichtdienst|wechselschicht|pflegekraft",
    re.I)
_AGE16 = re.compile(r"ab 16|mindestens 16|mind\. ?16|16 jahre|ab dem 16|ab dem vollendeten 16", re.I)
_AGE15 = re.compile(r"ab 15|mindestens 15|15 jahre", re.I)
_AGE13 = re.compile(r"ab 13|ab 14|mindestens 13|mindestens 14|13 jahre|14 jahre|13-|14-jährig", re.I)
# Verlangt die Anzeige eine Qualifikation, die Jugendliche nicht haben können?
_QUALIFIED = re.compile(
    r"abgeschlossene[sn]? (?:studium|ausbildung|berufsausbildung)|laufende[sn]? studium|lehramtsstudium|"
    r"studium (?:der|im bereich|abgeschlossen)|studierende (?:der|im)|abitur (?:ist |wird )?(?:voraus|erforderlich)|"
    r"(?:mehrjährige|einschlägige) berufserfahrung|berufserfahrung (?:ist |wird )?(?:erforderlich|vorausgesetzt)|"
    r"staatlich anerkannt|examinier|pädagogische (?:ausbildung|qualifikation)", re.I)
# Richtet sich die Anzeige ausdrücklich an Schüler als Bewerber?
_PUPIL = re.compile(r"für schüler|schüler(?:innen)?\s*(?:und|/|oder|&)\s*student|schülerjob|schüleraushilfe|"
                    r"als schüler|schüler(?:innen)? ab|schüler(?:innen)? gesucht|auch schüler", re.I)
_HOLIDAY = re.compile(r"ferienjob|ferienaushilfe|in den ferien|während der ferien|sommerferien|osterferien|"
                      r"herbstferien|weihnachtsferien|winterferien|saisonaushilfe|saisonkraft|ferienarbeit", re.I)
_MANY_HOURS = re.compile(r"vollzeit|(?:[3-9]|1\d)\s*(?:-\s*\d+\s*)?(?:std\.?|stunden)\s*(?:pro|am|/|je)?\s*tag|"
                         r"8[- ]stunden", re.I)

# ---- Verdächtige Angebote -----------------------------------------------------------------
_SCAM = re.compile(
    r"vorkasse|vorab .{0,20}(?:zahl|überweis)|anmeldegebühr|startgebühr|startpaket|startgeld|schnell reich|"
    r"reich werden|passives? einkommen|krypto|bitcoin|trading|forex|whatsapp|telegram|nur per chat|"
    r"paketagent|pakete? (?:an|weiter)|warenagent|finanzagent|bankkonto (?:zur verfügung|eröffnen)|"
    r"investier|multi.?level|network.?marketing|nur auf provision|reine provision|ohne risiko viel geld",
    re.I)

_PAY_HOUR = re.compile(r"(\d{1,2}(?:[,.]\d{1,2})?)\s*(?:€|euro)\s*(?:brutto\s*)?(?:/|pro|die|je)\s*(?:std|stunde)", re.I)
_PAY_MONTH = re.compile(r"(\d{3,4}(?:[,.]\d{2})?)\s*(?:€|euro)\s*(?:brutto\s*)?(?:/|pro|im|monatlich|je)\s*(?:monat)?", re.I)
_HOURS = re.compile(r"(\d{1,2}(?:[,.]5)?(?:\s*(?:-|–|bis)\s*\d{1,2})?)\s*(?:std\.?|stunden)\s*(?:pro|am|/|je|in der|die)?\s*"
                    r"(tag|woche|monat|nacht)", re.I)
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
_PHONE = re.compile(r"(?:\+49|\b0)\s?\d{2,5}[\s/-]?\d{3,}(?:[\s-]?\d{2,})*")


def job_type(text: str) -> str:
    for name, rx in JOB_TYPES:
        if re.search(rx, text, re.I):
            return name
    return "sonstiges"


def classify_age(title: str, text: str, jtype: str) -> tuple[int, str]:
    """-> (Mindestalter 13/15/16/18, kurze Begründung). Im Zweifel höher."""
    t = f"{title}\n{text}"
    if _ADULT.search(t):
        return 18, "Nachtarbeit, Führerschein oder ausdrücklich ab 18"
    if _AGE16.search(t):
        return 16, "laut Anzeige ab 16"
    if _AGE13.search(t) and jtype in LIGHT_TYPES and not _MANY_HOURS.search(t):
        return 13, "leichte Arbeit, laut Anzeige ab 13/14"
    if _QUALIFIED.search(t):
        return 18, "verlangt Studium, Abitur oder Berufserfahrung"
    # Bei Nachhilfe/Babysitten steht "Schüler" meist für die Kunden – dort zählt nur eine Altersangabe
    if jtype in ("nachhilfe", "babysitten"):
        return (15 if _AGE15.search(t) else 16), "Alter in der Anzeige nicht klar – beim Anbieter nachfragen"
    light = jtype in LIGHT_TYPES
    if light and not _MANY_HOURS.search(t):
        if _PUPIL.search(t):
            return 13, "leichte Arbeit, für Schüler ausgeschrieben"
        if not _AGE15.search(t):
            return 13, "leichte Arbeit – Alter in der Anzeige nicht genannt, beim Arbeitgeber nachfragen"
    if _AGE15.search(t) or _HOLIDAY.search(t):
        return 15, "Ferienjob (ab 15 max. 4 Wochen im Jahr)"
    if _PUPIL.search(t):
        return 16, "Schülerjob außerhalb der Ferien"
    return 18, "keine Hinweise, dass Jugendliche angesprochen sind"


def period_of(text: str, start: str) -> str:
    t = text.lower()
    if "weihnacht" in t or "winterferien" in t:
        return "Weihnachtsferien"
    if "oster" in t:
        return "Osterferien"
    if "sommerferien" in t or "sommerjob" in t:
        return "Sommerferien"
    if "herbstferien" in t:
        return "Herbstferien"
    if _HOLIDAY.search(t):
        try:
            m = dt.date.fromisoformat(start).month if start else 0
        except ValueError:
            m = 0
        return {12: "Weihnachtsferien", 1: "Weihnachtsferien", 3: "Osterferien", 4: "Osterferien",
                7: "Sommerferien", 8: "Sommerferien", 10: "Herbstferien"}.get(m, "Ferien")
    return "Nebenbei"


def pay_of(text: str) -> tuple[str, float | None]:
    m = _PAY_HOUR.search(text)
    if m:
        v = float(m.group(1).replace(",", "."))
        if 5 <= v <= 60:
            return f"{m.group(1)} € pro Stunde", v
    if re.search(r"mindestlohn", text, re.I):
        return "Mindestlohn", None
    m = _PAY_MONTH.search(text)
    if m and re.search(r"monat|minijob", text[max(0, m.start() - 60): m.end() + 30], re.I):
        return f"{m.group(1)} € im Monat", None
    return "", None


def hours_of(text: str, models: list[str]) -> str:
    m = _HOURS.search(text)
    if m:
        return C.clean_ws(f"{m.group(1)} Std. pro {m.group(2).capitalize()}")
    labels = {"TEILZEIT": "Teilzeit", "VOLLZEIT": "Vollzeit", "MINIJOB": "Minijob",
              "SCHICHT_NACHTARBEIT_WOCHENENDE": "Schicht/Wochenende", "HEIM_TELEARBEIT": "Homeoffice"}
    return ", ".join(labels.get(x, x.title()) for x in models)


# ---- Bundesagentur für Arbeit ---------------------------------------------------------------

def ba_search(s: requests.Session, term: str, wo: str, umkreis: int, size: int) -> list[dict[str, Any]]:
    params = {"was": term, "wo": wo, "umkreis": umkreis, "size": size, "page": 1, "angebotsart": 1,
              "veroeffentlichtseit": 60}
    try:
        r = s.get(f"{API}/pc/v6/jobs", params=params, headers=API_HEADERS, timeout=30)
        r.raise_for_status()
        return r.json().get("ergebnisliste", []) or []
    except (requests.RequestException, ValueError) as e:
        C.log(f"  Jobsuche '{term}' fehlgeschlagen: {e}")
        return []
    finally:
        time.sleep(API_DELAY)


def ba_details(s: requests.Session, ref: str) -> dict[str, Any]:
    code = base64.b64encode(ref.encode()).decode()
    try:
        r = s.get(f"{API}/pc/v4/jobdetails/{code}", headers=API_HEADERS, timeout=30)
        r.raise_for_status()
        return r.json()
    except (requests.RequestException, ValueError):
        return {}
    finally:
        time.sleep(API_DELAY)


# ---- KI-Einstufung (optional) -----------------------------------------------------------------

JOB_LLM_SYSTEM = """Du prüfst deutsche Stellenanzeigen für eine Jugend-App (Nutzer ab 13 Jahren).
Stufe nach dem Jugendarbeitsschutzgesetz ein:
 13 = mit 13/14 möglich: nur leichte Arbeit (Zeitungen/Prospekte austragen, Nachhilfe, Babysitten,
      Gartenarbeit, Hunde ausführen, Einkaufshilfe), max. 2 Std./Tag, nur 8–18 Uhr, nicht in der Schulzeit
 15 = Ferienjob ab 15 (max. 4 Wochen/Jahr, max. 8 Std./Tag, 40 Std./Woche)
 16 = ab 16      18 = ab 18 (Nachtarbeit, Arbeitsbeginn vor 6 Uhr, Führerschein, Alkohol, Sicherheit,
      oder die Anzeige richtet sich erkennbar an Erwachsene)
Im Zweifel IMMER die höhere Stufe. suspicious = true bei Vorkasse, Gebühren, "schnell reich werden",
Kryptowährung, Paket-/Finanzagent, nur Chat-Kontakt (WhatsApp/Telegram) oder fehlendem Arbeitgeber.
Erfinde nichts; unbekannte Felder bleiben leer."""

JOB_LLM_SCHEMA = {
    "type": "object",
    "properties": {
        "min_age": {"type": "integer", "enum": [13, 15, 16, 18]},
        "reason": {"type": "string"},
        "type": {"type": "string", "enum": [n for n, _ in JOB_TYPES] + ["sonstiges"]},
        "hours": {"type": "string"},
        "pay": {"type": "string"},
        "period": {"type": "string", "enum": ["Weihnachtsferien", "Osterferien", "Sommerferien",
                                              "Herbstferien", "Ferien", "Nebenbei"]},
        "suspicious": {"type": "boolean"},
    },
    "required": ["min_age", "reason", "type", "hours", "pay", "period", "suspicious"],
    "additionalProperties": False,
}


def llm_classify(claude: Any, title: str, employer: str, text: str) -> dict[str, Any] | None:
    if claude is None or claude.disabled:
        return None
    resp = claude._create(
        max_tokens=2000,
        system=JOB_LLM_SYSTEM,
        output_config={"effort": "low", "format": {"type": "json_schema", "schema": JOB_LLM_SCHEMA}},
        messages=[{"role": "user", "content": f"Titel: {title}\nArbeitgeber: {employer}\n\n{text[:12000]}"}],
    )
    if resp is None or resp.stop_reason in ("refusal", "max_tokens"):
        return None
    try:
        return json.loads("".join(b.text for b in resp.content if b.type == "text"))
    except json.JSONDecodeError:
        return None


# ---- Hauptablauf -------------------------------------------------------------------------------

def run(feed: Any, fetcher: Any, claude: Any, args: Any, geo: Any) -> None:
    cfg = feed.jobs
    s: requests.Session = fetcher.s
    out_file = args.out or (C.DATA_DIR / feed.output)
    stamp = C.NOW.isoformat(timespec="seconds")
    per_term = int(cfg.get("per_term", 50))
    max_details = int(cfg.get("max_details", 200))

    hits: dict[str, dict[str, Any]] = {}
    for place in cfg.get("places", []):
        for term in cfg.get("terms", []):
            res = ba_search(s, term, place["wo"], int(place.get("umkreis", 25)), per_term)
            C.log(f"  '{term}' in {place['wo']}: {len(res)} Treffer")
            for j in res:
                ref = j.get("referenznummer") or j.get("refnr")
                if ref and ref not in hits:
                    hits[ref] = j

    C.log(f"{len(hits)} verschiedene Anzeigen – lese Details")
    jobs: list[dict[str, Any]] = []
    dropped = {"scam": 0, "no_employer": 0}
    # Leichte Jobs zuerst genauer lesen (die sind für Jüngere interessant)
    ordered = sorted(hits.values(), key=lambda j: job_type(j.get("stellenangebotsTitel", "")) not in LIGHT_TYPES)
    for j in ordered[:max_details]:
        ref = j.get("referenznummer") or j.get("refnr")
        title = C.clean_ws(j.get("stellenangebotsTitel") or j.get("titel") or j.get("hauptberuf"))
        employer = C.clean_ws(j.get("firma") or j.get("arbeitgeber"))
        if not employer:
            dropped["no_employer"] += 1
            continue
        det = ba_details(s, ref)
        desc = C.clean_ws(det.get("stellenangebotsBeschreibung") or det.get("stellenbeschreibung") or "")
        models = [m for m in (det.get("arbeitszeitmodelle") or []) if isinstance(m, str)]
        text = f"{title}\n{j.get('hauptberuf', '')}\n{desc}"
        if _SCAM.search(text):
            dropped["scam"] += 1
            continue
        jtype = job_type(title + " " + j.get("hauptberuf", "")) if job_type(title) == "sonstiges" else job_type(title)
        min_age, reason = classify_age(title, text, jtype)
        start = (j.get("eintrittszeitraum") or {}).get("von", "") or det.get("eintrittsdatum", "")
        pay, pay_hour = pay_of(desc)
        hours = hours_of(desc, models)
        period = period_of(text, start)

        ai = llm_classify(claude, title, employer, text)
        if ai:
            if ai.get("suspicious"):
                dropped["scam"] += 1
                continue
            # Die KI darf nur strenger sein als die festen Regeln, nie lockerer
            if int(ai.get("min_age", 18)) > min_age:
                min_age, reason = int(ai["min_age"]), C.clean_ws(ai.get("reason")) or reason
            jtype = ai.get("type") or jtype
            hours = C.clean_ws(ai.get("hours")) or hours
            pay = C.clean_ws(ai.get("pay")) or pay
            period = ai.get("period") or period

        loc = (j.get("stellenlokationen") or [{}])[0]
        adr = loc.get("adresse", {}) or {}
        lat, lng = loc.get("breite"), loc.get("laenge")
        city = C.clean_ws(adr.get("ort"))
        street = C.clean_ws(adr.get("strasse"))
        address = ", ".join(x for x in (street, f"{adr.get('plz', '')} {city}".strip()) if x)
        emails = _EMAIL.findall(desc)
        phones = [p for p in _PHONE.findall(desc) if len(re.sub(r"\D", "", p)) >= 7]
        contact = ", ".join(dict.fromkeys(emails[:1] + phones[:1])) or "über die Jobbörse der Arbeitsagentur"
        jobs.append({
            "id": f"ba-{ref}",
            "title": C.short(title, 120),
            "employer": C.short(employer, 100),
            "type": jtype,
            "minAge": min_age,
            "ageReason": reason,
            "city": city,
            "address": address,
            "lat": round(float(lat), 6) if lat is not None else None,
            "lng": round(float(lng), 6) if lng is not None else None,
            "hours": C.short(hours, 80),
            "pay": C.short(pay, 60),
            "payPerHour": pay_hour,
            "period": period,
            "start": start,
            "published": (j.get("veroeffentlichungszeitraum") or {}).get("von", ""),
            "url": det.get("externeUrl") or JOB_LINK.format(ref=ref),
            "contact": C.short(contact, 120),
            "description": C.short(desc, 320),
            "source": "Bundesagentur für Arbeit",
            "firstSeen": stamp,
            "lastSeen": stamp,
        })

    # mit dem letzten Stand zusammenführen (firstSeen behalten, kurz verschwundene Anzeigen halten)
    old: list[dict[str, Any]] = []
    if out_file.exists() and not args.only:
        try:
            old = json.loads(out_file.read_text("utf-8")).get("jobs", [])
        except (json.JSONDecodeError, ValueError):
            old = []
    by_id = {j["id"]: j for j in jobs}
    forget = (C.NOW - dt.timedelta(days=int(cfg.get("forget_after_days", 4)))).isoformat()
    for o in old:
        if o["id"] in by_id:
            by_id[o["id"]]["firstSeen"] = o.get("firstSeen") or stamp
        elif (o.get("lastSeen") or "") >= forget:
            by_id[o["id"]] = o
    # Doppelte Anzeigen (gleicher Arbeitgeber + Titel + Ort) zusammenführen
    seen: dict[str, dict[str, Any]] = {}
    for j in by_id.values():
        key = C.norm(j["employer"]) + "|" + C.norm(j["title"]) + "|" + C.norm(j["city"])
        if key not in seen or j["lastSeen"] > seen[key]["lastSeen"]:
            seen[key] = j
    result = sorted(seen.values(), key=lambda j: (j["minAge"], j["title"]))

    payload = {"version": 1, "feed": feed.name, "title": feed.title, "generated": stamp,
               "count": len(result), "source": "Jobsuche der Bundesagentur für Arbeit",
               "ageRule": "minAge 13 = ab 13/14 möglich (leichte Arbeit), 15 = Ferienjob ab 15, 16, 18",
               "jobs": result}
    by_age: dict[int, int] = {}
    for j in result:
        by_age[j["minAge"]] = by_age.get(j["minAge"], 0) + 1
    C.log(f"Fertig (jobs): {len(result)} Jobs, nach Alter {dict(sorted(by_age.items()))}, verworfen {dropped}")
    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    out_file.write_text(json.dumps(payload, ensure_ascii=False, indent=1), "utf-8")
    C.log(f"Gespeichert: {out_file}")
