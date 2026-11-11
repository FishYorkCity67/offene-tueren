#!/usr/bin/env python3
"""Offene Türen – sammelt Termine für Tage der offenen Tür in ganz Deutschland.

Ablauf (läuft täglich über GitHub Actions, siehe .github/workflows/update-events.yml):
  1. Quellen laden: feste Liste (sources.yaml), handgeprüfte Termine (manual_events.yaml)
     und – wenn ein Claude-API-Schlüssel da ist – Treffer einer Websuche.
  2. Jede Seite nur abrufen, wenn robots.txt es erlaubt (mit Pause pro Website).
  3. Termine herausziehen: strukturierte Daten (schema.org/JSON-LD, iCal), sonst
     Claude (falls Schlüssel vorhanden), sonst eine einfache Text-Erkennung.
  4. Aufräumen: Kategorie und Altersfreigabe bestimmen, Fachpublikum aussortieren,
     Adressen in Koordinaten umwandeln (OpenStreetMap Nominatim), doppelte Einträge
     zusammenführen, vergangene Termine löschen.
  5. Ergebnis nach data/events.json schreiben – diese Datei lädt die App.

Aufruf lokal:  python crawler/crawl.py [--no-llm] [--no-search] [--only URL] [--max-pages N]
"""
from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import io
import json
import math
import os
import re
import sys
import time
import unicodedata
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urljoin, urlparse, urldefrag
from zoneinfo import ZoneInfo

import requests
import yaml
from bs4 import BeautifulSoup
from dateutil import parser as dateparser

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
EVENTS_FILE = DATA_DIR / "events.json"
GEOCACHE_FILE = DATA_DIR / "geocache.json"
SOURCES_FILE = ROOT / "crawler" / "sources.yaml"
MANUAL_FILE = ROOT / "crawler" / "manual_events.yaml"

TZ = ZoneInfo("Europe/Berlin")
NOW = dt.datetime.now(TZ)
TODAY = NOW.date()
HORIZON_DAYS = 400          # weiter in der Zukunft liegende Daten sind fast immer Lesefehler
FORGET_AFTER_DAYS = 45      # Termine, die so lange auf keiner Quelle mehr auftauchen, fliegen raus

_repo = os.environ.get("GITHUB_REPOSITORY")
USER_AGENT = os.environ.get(
    "CRAWLER_USER_AGENT",
    f"OffeneTuerenBot/1.0 (+https://github.com/{_repo})" if _repo
    else "OffeneTuerenBot/1.0 (privates Schulprojekt, nicht-kommerziell)",
)
HTTP_TIMEOUT = 25
MIN_DELAY_PER_HOST = 2.0    # Sekunden zwischen zwei Abrufen derselben Website
MAX_BYTES = 6_000_000

# Wörter, an denen man eine Seite über einen Tag der offenen Tür erkennt.
KEYWORDS = [
    "tag der offenen tür", "tag der offenen tuer", "tag der offenen türen", "tage der offenen tür",
    "tag der offenen tore", "tag der offenen schule", "tag der offenen hörsäle",
    "hochschulinformationstag", "hochschulinfotag", "hochschultag", "studieninformationstag",
    "studieninfotag", "studientag für schüler", "schnupperstudium", "schnuppertag", "schnupperuni",
    "unilive", "uni live", "campustag", "open campus", "open day", "infotag", "informationstag",
    "ausbildungsmesse", "ausbildungstag", "azubitag", "berufsinformationstag", "berufsinfotag",
    "fachmesse für ausbildung", "messe für ausbildung", "ausbildungs- und studienmesse", "studienmesse",
    "berufsmesse", "berufsorientierungsmesse", "azubi- & studientage", "azubi- und studientage",
    "vocatium", "einstieg messe", "ausbildungsbörse", "ausbildungsplatzbörse", "nacht der ausbildung",
    "betriebsbesichtigung", "werksbesichtigung", "lange nacht der wissenschaft",
    "lange nacht der forschung", "lange nacht der museen",
]
_KW_RE = re.compile("|".join(re.escape(k) for k in KEYWORDS), re.I)

CATEGORIES = ("hochschule", "schule", "ausbildung", "sonstiges")


# --------------------------------------------------------------------------------------
# Hilfsfunktionen
# --------------------------------------------------------------------------------------

def log(*args: Any) -> None:
    print(*args, file=sys.stderr, flush=True)


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("ß", "ss")
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def clean_ws(s: str | None) -> str:
    return re.sub(r"\s+", " ", s or "").strip()


def short(s: str, n: int) -> str:
    s = clean_ws(s)
    return s if len(s) <= n else s[: n - 1].rsplit(" ", 1)[0] + " …"


def in_germany(lat: float | None, lng: float | None) -> bool:
    return lat is not None and lng is not None and 47.2 <= lat <= 55.1 and 5.8 <= lng <= 15.1


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    r = 6371.0
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


# --------------------------------------------------------------------------------------
# Datenmodell
# --------------------------------------------------------------------------------------

@dataclass
class Event:
    title: str
    org: str
    category: str
    date: dt.date
    end_date: dt.date | None = None
    start_time: str = ""        # "HH:MM" oder leer
    end_time: str = ""
    address: str = ""
    city: str = ""
    lat: float | None = None
    lng: float | None = None
    url: str = ""
    min_age: int | None = None  # None = keine Altersgrenze bekannt
    audience: str = "alle"
    needs_adult: bool = False
    description: str = ""
    sources: list[str] = field(default_factory=list)
    first_seen: str = ""
    last_seen: str = ""
    manual: bool = False

    # -- Zeiten ------------------------------------------------------------------------
    def start_dt(self) -> dt.datetime:
        h, m = (int(x) for x in self.start_time.split(":")) if self.start_time else (0, 0)
        return dt.datetime.combine(self.date, dt.time(h, m), TZ)

    def end_dt(self) -> dt.datetime:
        day = self.end_date or self.date
        if self.end_time:
            h, m = (int(x) for x in self.end_time.split(":"))
            return dt.datetime.combine(day, dt.time(h, m), TZ)
        return dt.datetime.combine(day, dt.time(23, 59), TZ)

    def key(self) -> str:
        base = norm(self.org or self.title) + "|" + self.date.isoformat() + "|" + norm(self.city)
        return hashlib.sha1(base.encode()).hexdigest()[:14]

    def to_json(self) -> dict[str, Any]:
        all_day = not self.start_time
        return {
            "id": self.key(),
            "title": self.title,
            "org": self.org,
            "category": self.category,
            "start": self.start_dt().isoformat(),
            "end": self.end_dt().isoformat(),
            "allDay": all_day,
            "address": self.address,
            "city": self.city,
            "lat": round(self.lat, 6) if self.lat is not None else None,
            "lng": round(self.lng, 6) if self.lng is not None else None,
            "url": self.url,
            "minAge": self.min_age,
            "audience": self.audience,
            "needsAdult": self.needs_adult,
            "description": self.description,
            "sources": self.sources[:5],
            "firstSeen": self.first_seen,
            "lastSeen": self.last_seen,
            "verified": self.manual,
        }

    @staticmethod
    def from_json(d: dict[str, Any]) -> "Event":
        start = dt.datetime.fromisoformat(d["start"]).astimezone(TZ)
        end = dt.datetime.fromisoformat(d["end"]).astimezone(TZ) if d.get("end") else None
        all_day = d.get("allDay", False)
        e = Event(
            title=d.get("title", ""), org=d.get("org", ""), category=d.get("category", "sonstiges"),
            date=start.date(),
            end_date=end.date() if end and end.date() != start.date() else None,
            start_time="" if all_day else start.strftime("%H:%M"),
            end_time="" if (all_day or not end or end.strftime("%H:%M") == "23:59") else end.strftime("%H:%M"),
            address=d.get("address", ""), city=d.get("city", ""), lat=d.get("lat"), lng=d.get("lng"),
            url=d.get("url", ""), min_age=d.get("minAge"), audience=d.get("audience", "alle"),
            needs_adult=bool(d.get("needsAdult")), description=d.get("description", ""),
            sources=list(d.get("sources", [])), first_seen=d.get("firstSeen", ""),
            last_seen=d.get("lastSeen", ""), manual=bool(d.get("verified")),
        )
        return e


# --------------------------------------------------------------------------------------
# Höfliches Abrufen (robots.txt, Pausen, Größenlimit)
# --------------------------------------------------------------------------------------

class Robots:
    """robots.txt-Auswertung mit Platzhaltern (* und $), wie sie Suchmaschinen verstehen.

    Pythons urllib.robotparser kennt keine Platzhalter und würde z. B. "Disallow: /*search"
    ignorieren – deshalb eine eigene, strengere Umsetzung (RFC 9309).
    """

    BOT = "offenetuerenbot"

    def __init__(self, lines: list[str] | None, deny_all: bool = False):
        self.deny_all = deny_all
        self.rules: list[tuple[bool, re.Pattern[str], int]] = []
        self.delay: float | None = None
        if lines is not None:
            self._parse(lines)

    def _parse(self, lines: list[str]) -> None:
        groups: list[tuple[list[str], list[tuple[str, str]]]] = []
        agents: list[str] = []
        rules: list[tuple[str, str]] = []
        last_was_rule = False
        for raw in lines:
            line = raw.split("#", 1)[0].strip()
            if ":" not in line:
                continue
            k, v = (x.strip() for x in line.split(":", 1))
            k = k.lower()
            if k == "user-agent":
                if last_was_rule:
                    groups.append((agents, rules))
                    agents, rules = [], []
                agents.append(v.lower())
                last_was_rule = False
            elif k in ("allow", "disallow", "crawl-delay"):
                rules.append((k, v))
                last_was_rule = True
        if agents:
            groups.append((agents, rules))
        mine = [r for a, r in groups if any(x != "*" and x in self.BOT for x in a)]
        chosen = mine or [r for a, r in groups if "*" in a]
        for group in chosen:
            for k, v in group:
                if k == "crawl-delay":
                    try:
                        self.delay = max(self.delay or 0, float(v))
                    except ValueError:
                        pass
                elif v or k == "allow":
                    if k == "disallow" and not v:
                        continue
                    pat = re.escape(v).replace(r"\*", ".*")
                    if pat.endswith(r"\$"):
                        pat = pat[:-2] + "$"
                    self.rules.append((k == "allow", re.compile(pat), len(v)))

    def can_fetch(self, url: str) -> bool:
        if self.deny_all:
            return False
        p = urlparse(url)
        path = (p.path or "/") + (("?" + p.query) if p.query else "")
        best: tuple[int, bool] | None = None
        for allow, rx, length in self.rules:
            if rx.match(path):
                if best is None or length > best[0] or (length == best[0] and allow):
                    best = (length, allow)
        return True if best is None else best[1]


class PoliteFetcher:
    def __init__(self, blocked_domains: Iterable[str]):
        self.s = requests.Session()
        self.s.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "de-DE,de;q=0.9"})
        self.robots: dict[str, Robots | None] = {}
        self.last_hit: dict[str, float] = {}
        self.blocked = {d.lower().lstrip(".") for d in blocked_domains}
        self.stats = {"fetched": 0, "robots_denied": 0, "errors": 0, "blocked": 0}

    def _host_blocked(self, host: str) -> bool:
        host = host.lower()
        return any(host == d or host.endswith("." + d) for d in self.blocked)

    def _robots_for(self, scheme: str, host: str) -> Robots | None:
        base = f"{scheme}://{host}"
        if base in self.robots:
            return self.robots[base]
        rp: Robots | None
        try:
            r = self.s.get(base + "/robots.txt", timeout=HTTP_TIMEOUT)
            if r.status_code in (401, 403):
                rp = Robots(None, deny_all=True)                     # gesperrt -> nichts abrufen
            elif r.status_code >= 500:
                rp = None                                            # Serverfehler -> lieber nicht
            elif r.status_code >= 400:
                rp = Robots([])                                      # keine robots.txt -> erlaubt
            else:
                rp = Robots(r.text.splitlines())
        except requests.RequestException:
            rp = None                                                # nicht erreichbar -> Seite überspringen
        self.robots[base] = rp
        return rp

    def allowed(self, url: str) -> bool:
        p = urlparse(url)
        if p.scheme not in ("http", "https") or not p.netloc:
            return False
        if self._host_blocked(p.netloc):
            self.stats["blocked"] += 1
            return False
        rp = self._robots_for(p.scheme, p.netloc)
        if rp is None or not rp.can_fetch(url):
            self.stats["robots_denied"] += 1
            return False
        return True

    def get(self, url: str) -> requests.Response | None:
        if not self.allowed(url):
            log(f"  übersprungen (robots.txt/Sperrliste): {url}")
            return None
        p = urlparse(url)
        rp = self.robots.get(f"{p.scheme}://{p.netloc}")
        delay = MIN_DELAY_PER_HOST
        if rp is not None and rp.delay:
            if rp.delay > 60:
                log(f"  übersprungen (Crawl-delay {rp.delay:.0f} s zu lang): {url}")
                return None
            delay = max(delay, rp.delay)
        wait = self.last_hit.get(p.netloc, 0) + delay - time.time()
        if wait > 0:
            time.sleep(wait)
        self.last_hit[p.netloc] = time.time()
        try:
            r = self.s.get(url, timeout=HTTP_TIMEOUT, stream=True)
            body = r.raw.read(MAX_BYTES + 1, decode_content=True)
            r._content = body[:MAX_BYTES]
            if r.status_code >= 400:
                log(f"  HTTP {r.status_code}: {url}")
                self.stats["errors"] += 1
                return None
            self.stats["fetched"] += 1
            return r
        except requests.RequestException as e:
            log(f"  Fehler {type(e).__name__}: {url}")
            self.stats["errors"] += 1
            return None


# --------------------------------------------------------------------------------------
# Einordnung: Kategorie und Altersfreigabe
# --------------------------------------------------------------------------------------

_HOCHSCHULE = ["universität", "universitaet", "hochschule", "fachhochschule", "uni ", "tu ", "kit ",
               "rwth", "akademie", "studium", "studien", "hochschulinformationstag", "hochschulinfotag",
               "schnupperstudium", "campus", "berufsakademie", "duale hochschule", "lmu", "fh "]
_SONSTIGES = ["feuerwehr", "polizei", "bundeswehr", "kaserne", "rathaus", "museum", "fraunhofer",
              "max-planck", "max planck", "helmholtz", "leibniz", "forschungszentrum", "institut", "dlr",
              "landtag", "bundestag", "ministerium", "sternwarte", "planetarium", "theater", "zoo",
              "klärwerk", "kläranlage", "thw", "drk", "rettungswache", "flughafen", "bahnhof", "gericht"]
_SCHULE = ["gymnasium", "gesamtschule", "realschule", "oberschule", "gemeinschaftsschule", "sekundarschule",
           "stadtteilschule", "berufsschule", "berufskolleg", "berufsbildende schule", "bbs ", "schulzentrum",
           "mittelschule", "regelschule", "werkrealschule", "fachoberschule", "schule"]
_AUSBILDUNG = ["ausbildung", "azubi", "ausbildungsmesse", "betrieb", "unternehmen", "gmbh", " ag ", " ag,",
               " kg", "werk ", "werksbesichtigung", "betriebsbesichtigung", "handwerk", "ihk", "hwk",
               "firma", "berufsinformationstag", "jobmesse", "karrieretag"]


_MESSE = ["ausbildungsmesse", "messe für ausbildung", "fachmesse für ausbildung", "berufsmesse", "azubi",
          "vocatium", "ausbildungsbörse", "ausbildungsplatzbörse", "jobmesse", "karrieremesse", "nacht der ausbildung"]


def classify(*texts: str, hint: str | None = None) -> str:
    if hint in CATEGORIES:
        return hint
    t = " " + " ".join(x for x in texts if x).lower() + " "
    if any(w in t for w in _MESSE):          # Messen nennen oft auch „Studium“ – trotzdem Ausbildung
        return "ausbildung"
    if any(w in t for w in _HOCHSCHULE):
        return "hochschule"
    if any(w in t for w in _SONSTIGES):
        return "sonstiges"
    if any(w in t for w in _SCHULE):
        return "schule"
    if any(w in t for w in _AUSBILDUNG):
        return "ausbildung"
    return "sonstiges"


_MIN_AGE_RES = [
    re.compile(r"\b(?:erst\s+)?ab\s+(\d{1,2})\s*(?:jahren|jahre|j\.)", re.I),
    re.compile(r"\bmindestalter\s*:?\s*(\d{1,2})", re.I),
    re.compile(r"\b(?:teilnahme|zutritt|eintritt|einlass)\s+(?:erst\s+)?ab\s+(\d{1,2})\b(?!\s*(?:uhr|:|\.\d))", re.I),
    re.compile(r"\bfsk\s*(\d{1,2})\b", re.I),
    re.compile(r"\b(\d{2})\s*\+\s*(?:jahre|veranstaltung|event)", re.I),
]
_ADULTS_ONLY = re.compile(r"nur\s+für\s+(?:volljährige|erwachsene)|ausschließlich\s+volljährig", re.I)
_PRO_ONLY = re.compile(
    r"fachpublikum|fachbesucher|nur\s+für\s+fachleute|nur\s+für\s+(?:mitarbeitende|mitarbeiter|beschäftigte)"
    r"|nur\s+für\s+geladene\s+gäste|geschlossene\s+veranstaltung|nicht\s+öffentlich|b2b", re.I)
_NEEDS_ADULT = re.compile(
    r"in\s+begleitung\s+(?:eines|einer|von|der|ihrer|ihres|mit)?\s*(?:erwachsenen|eltern|erziehungsberechtigt)"
    r"|nur\s+(?:mit|in\s+begleitung)\s+(?:eines|einer)?\s*(?:erwachsenen|erziehungsberechtigt)"
    r"|(?:unter|bis)\s+\d{1,2}\s+(?:jahren|jahre)?\s*nur\s+(?:mit|in\s+begleitung)"
    r"|minderjährige\s+nur\s+(?:mit|in\s+begleitung)", re.I)
_PUBLIC_HINT = re.compile(r"familie|für\s+alle|jedermann|bürgerinnen|bürger|besucherinnen\s+und\s+besucher|öffentlich", re.I)


def age_info(text: str) -> tuple[int | None, bool, bool]:
    """-> (Mindestalter, nur Fachpublikum, Begleitung nötig)"""
    t = text or ""
    min_age: int | None = None
    for rx in _MIN_AGE_RES:
        for m in rx.finditer(t):
            n = int(m.group(1))
            if 6 <= n <= 21:
                # "unter 16 nur in Begleitung" ist keine Grenze, sondern ein Begleit-Hinweis
                before = t[max(0, m.start() - 25): m.start()].lower()
                if "unter" in before or "bis" in before:
                    continue
                min_age = max(min_age or 0, n)
    if _ADULTS_ONLY.search(t):
        min_age = max(min_age or 0, 18)
    pro_only = bool(_PRO_ONLY.search(t))
    needs_adult = bool(_NEEDS_ADULT.search(t))
    return min_age, pro_only, needs_adult


def bundeswehr_ok(text: str, min_age: int | None) -> bool:
    """Bundeswehr nur, wenn ausdrücklich für alle/Familien oder Mindestalter ≤ 14."""
    t = (text or "").lower()
    if "bundeswehr" not in t and "kaserne" not in t:
        return True
    if min_age is not None:
        return min_age <= 14
    return bool(_PUBLIC_HINT.search(t))


# --------------------------------------------------------------------------------------
# Datum/Uhrzeit aus Freitext
# --------------------------------------------------------------------------------------

MONTHS = {"januar": 1, "jan": 1, "jänner": 1, "februar": 2, "feb": 2, "märz": 3, "maerz": 3, "mär": 3,
          "april": 4, "apr": 4, "mai": 5, "juni": 6, "jun": 6, "juli": 7, "jul": 7, "august": 8, "aug": 8,
          "september": 9, "sep": 9, "sept": 9, "oktober": 10, "okt": 10, "november": 11, "nov": 11,
          "dezember": 12, "dez": 12}
_MONTH_ALT = "|".join(sorted((re.escape(k) for k in MONTHS), key=len, reverse=True))
_DATE_WORD = re.compile(rf"\b(\d{{1,2}})\.\s*({_MONTH_ALT})\.?\s*(\d{{4}})?", re.I)
_DATE_NUM = re.compile(r"\b(\d{1,2})\.\s?(\d{1,2})\.(\d{4}|\d{2})?(?!\d)")
_TIME_RANGE = re.compile(
    r"\b(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?\s*(?:-|–|—|bis)\s*(\d{1,2})(?:[:.](\d{2}))?\s*uhr", re.I)
_TIME_SINGLE = re.compile(r"\b(?:ab|um|beginn:?)\s*(\d{1,2})(?:[:.](\d{2}))?\s*uhr", re.I)


def _mk_date(d: int, m: int, y: int | None) -> dt.date | None:
    try:
        if y is None:
            cand = dt.date(TODAY.year, m, d)
            if cand < TODAY - dt.timedelta(days=1):
                cand = dt.date(TODAY.year + 1, m, d)
            return cand
        if y < 100:
            y += 2000
        return dt.date(y, m, d)
    except ValueError:
        return None


_DATE_RANGE_WORD = re.compile(
    rf"\b(\d{{1,2}})\.?\s*(?:und|bis|-|–|—|/|\+|&)\s*(\d{{1,2}})\.\s*({_MONTH_ALT})\.?\s*(\d{{4}})?", re.I)


def find_dates(text: str) -> list[tuple[int, dt.date]]:
    out: list[tuple[int, dt.date]] = []
    for m in _DATE_RANGE_WORD.finditer(text):       # "27. und 28. Januar 2027"
        mon = MONTHS[m.group(3).lower().rstrip(".")]
        y = int(m.group(4)) if m.group(4) else None
        d1, d2 = _mk_date(int(m.group(1)), mon, y), _mk_date(int(m.group(2)), mon, y)
        if d1 and d2 and d1 < d2:
            out += [(m.start(), d1), (m.start() + 1, d2)]
    for m in _DATE_WORD.finditer(text):
        d = _mk_date(int(m.group(1)), MONTHS[m.group(2).lower().rstrip(".")], int(m.group(3)) if m.group(3) else None)
        if d:
            out.append((m.start(), d))
    for m in _DATE_NUM.finditer(text):
        dd, mm = int(m.group(1)), int(m.group(2))
        if not (1 <= mm <= 12):
            continue
        d = _mk_date(dd, mm, int(m.group(3)) if m.group(3) else None)
        if d:
            out.append((m.start(), d))
    # gleiche Stelle doppelt (Bereich + Einzeldatum) -> nur einmal
    uniq: dict[tuple[int, dt.date], None] = {}
    for pos, d in sorted(out):
        uniq[(pos, d)] = None
    return list(uniq)


def find_times(text: str) -> tuple[str, str]:
    m = _TIME_RANGE.search(text)
    if m:
        h1, m1, h2, m2 = int(m.group(1)), int(m.group(2) or 0), int(m.group(3)), int(m.group(4) or 0)
        if 6 <= h1 <= 23 and 7 <= h2 <= 24 and (h2, m2) > (h1, m1):
            return f"{h1:02d}:{m1:02d}", (f"{h2:02d}:{m2:02d}" if h2 < 24 else "23:59")
    m = _TIME_SINGLE.search(text)
    if m:
        h, mi = int(m.group(1)), int(m.group(2) or 0)
        if 6 <= h <= 22:
            return f"{h:02d}:{mi:02d}", ""
    return "", ""


_ADDR = re.compile(
    r"([A-ZÄÖÜ][\wäöüß.\-]*(?:[ \-][\wäöüß.\-]+){0,4}?(?:straße|strasse|str\.|weg|platz|allee|ring|gasse|damm|ufer|"
    r"chaussee|steig|pfad|markt|berg|hof|kamp|tor)\s*\d{1,4}\s?[a-zA-Z]?)\s*[,|]?\s*(?:D-)?(\d{5})\s+"
    r"([A-ZÄÖÜ][\wäöüß.\-]+(?:\s(?:am|an der|im|bei|ob der)\s[A-ZÄÖÜ][\wäöüß.\-]+|\s\([^)]{1,25}\))?)")
_PLZ_CITY = re.compile(r"\b(?:D-)?(\d{5})\s+([A-ZÄÖÜ][a-zäöüß]+(?:[ \-][A-ZÄÖÜ][a-zäöüß]+)?)")


def find_address(text: str) -> tuple[str, str]:
    m = _ADDR.search(text)
    if m:
        return f"{clean_ws(m.group(1))}, {m.group(2)} {clean_ws(m.group(3))}", clean_ws(m.group(3))
    m = _PLZ_CITY.search(text)
    if m:
        return f"{m.group(1)} {m.group(2)}", m.group(2)
    return "", ""


# --------------------------------------------------------------------------------------
# Strukturierte Daten: JSON-LD (schema.org Event) und iCal
# --------------------------------------------------------------------------------------

def _as_list(x: Any) -> list[Any]:
    return x if isinstance(x, list) else ([] if x is None else [x])


def _walk_jsonld(node: Any) -> Iterable[dict[str, Any]]:
    if isinstance(node, list):
        for n in node:
            yield from _walk_jsonld(n)
    elif isinstance(node, dict):
        yield node
        for k in ("@graph", "itemListElement", "item", "subEvent", "event", "events"):
            if k in node:
                yield from _walk_jsonld(node[k])


def _is_event_type(t: Any) -> bool:
    return any(isinstance(x, str) and x.endswith("Event") for x in _as_list(t))


def _text_of(x: Any) -> str:
    if isinstance(x, str):
        return x
    if isinstance(x, dict):
        return str(x.get("name") or x.get("@value") or "")
    if isinstance(x, list) and x:
        return _text_of(x[0])
    return ""


def _parse_iso(s: Any) -> dt.datetime | dt.date | None:
    if not isinstance(s, str) or not s.strip():
        return None
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s.strip()):
            return dt.date.fromisoformat(s.strip())
        v = dateparser.isoparse(s.strip())
        return v.astimezone(TZ) if v.tzinfo else v.replace(tzinfo=TZ)
    except (ValueError, OverflowError):
        return None


def _split_dt(v: dt.datetime | dt.date | None) -> tuple[dt.date | None, str]:
    if v is None:
        return None, ""
    if isinstance(v, dt.datetime):
        t = v.strftime("%H:%M")
        return v.date(), ("" if t == "00:00" else t)
    return v, ""


def events_from_jsonld(soup: BeautifulSoup, page_url: str, hint: str | None, require_kw: bool) -> list[Event]:
    out: list[Event] = []
    for tag in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(tag.string or tag.get_text() or "")
        except (json.JSONDecodeError, TypeError):
            continue
        for node in _walk_jsonld(data):
            if not _is_event_type(node.get("@type")):
                continue
            name = clean_ws(_text_of(node.get("name")))
            desc = clean_ws(BeautifulSoup(_text_of(node.get("description")), "html.parser").get_text(" "))
            if require_kw and not _KW_RE.search(name + " " + desc):
                continue
            d, st = _split_dt(_parse_iso(node.get("startDate")))
            if d is None:
                continue
            ed, et = _split_dt(_parse_iso(node.get("endDate")))
            loc = _as_list(node.get("location"))
            loc = loc[0] if loc else {}
            address, city, lat, lng = "", "", None, None
            loc_name = ""
            if isinstance(loc, dict):
                loc_name = clean_ws(_text_of(loc.get("name")))
                a = loc.get("address")
                if isinstance(a, dict):
                    street = clean_ws(a.get("streetAddress"))
                    plz = clean_ws(a.get("postalCode"))
                    city = clean_ws(a.get("addressLocality"))
                    address = ", ".join(x for x in (street, f"{plz} {city}".strip()) if x)
                elif isinstance(a, str):
                    address = clean_ws(a)
                    _, city = find_address(address)
                g = loc.get("geo")
                if isinstance(g, dict):
                    try:
                        lat, lng = float(g.get("latitude")), float(g.get("longitude"))
                    except (TypeError, ValueError):
                        lat = lng = None
            elif isinstance(loc, str):
                address = clean_ws(loc)
            org = clean_ws(_text_of(node.get("organizer"))) or loc_name or name
            age_txt = " ".join([name, desc, _text_of(node.get("typicalAgeRange")), _text_of(node.get("audience"))])
            min_age, pro, adult = age_info(age_txt)
            tar = _text_of(node.get("typicalAgeRange"))
            m = re.match(r"\s*(\d{1,2})\s*-", tar or "")
            if m:
                min_age = max(min_age or 0, int(m.group(1)))
            if pro:
                continue
            out.append(Event(
                title=name or "Tag der offenen Tür", org=org,
                category=classify(name, org, desc, hint=hint), date=d,
                end_date=ed if ed and ed != d else None, start_time=st, end_time=et if ed == d or ed is None else "",
                address=address, city=city, lat=lat, lng=lng,
                url=urljoin(page_url, _text_of(node.get("url")) or page_url),
                min_age=min_age, needs_adult=adult, description=short(desc, 280), sources=[page_url],
            ))
    return out


def events_from_ics(content: bytes, page_url: str, hint: str | None) -> list[Event]:
    from icalendar import Calendar
    out: list[Event] = []
    try:
        cal = Calendar.from_ical(content)
    except Exception as e:  # noqa: BLE001 – kaputte Kalender einfach überspringen
        log(f"  iCal unlesbar ({e}): {page_url}")
        return out
    for comp in cal.walk("VEVENT"):
        summary = clean_ws(str(comp.get("SUMMARY", "")))
        desc = clean_ws(str(comp.get("DESCRIPTION", "")))
        if not _KW_RE.search(summary + " " + desc):
            continue
        start = comp.decoded("DTSTART", None)
        if start is None:
            continue
        if isinstance(start, dt.datetime):
            start = start.astimezone(TZ) if start.tzinfo else start.replace(tzinfo=TZ)
        end = comp.decoded("DTEND", None)
        if isinstance(end, dt.datetime):
            end = end.astimezone(TZ) if end.tzinfo else end.replace(tzinfo=TZ)
        elif isinstance(end, dt.date):
            end = end - dt.timedelta(days=1)          # iCal-Ganztagsende ist exklusiv
        d, st = _split_dt(start)
        ed, et = _split_dt(end)
        location = clean_ws(str(comp.get("LOCATION", "")))
        _, city = find_address(location)
        lat = lng = None
        geo = comp.get("GEO")
        if geo is not None:
            try:
                lat, lng = float(geo.latitude), float(geo.longitude)
            except (AttributeError, TypeError, ValueError):
                pass
        min_age, pro, adult = age_info(summary + " " + desc)
        if pro or d is None:
            continue
        org = location.split(",")[0] if location else summary
        out.append(Event(
            title=summary, org=org, category=classify(summary, location, desc, hint=hint), date=d,
            end_date=ed if ed and ed != d else None, start_time=st, end_time=et if (ed == d) else "",
            address=location, city=city, lat=lat, lng=lng, url=str(comp.get("URL", "")) or page_url,
            min_age=min_age, needs_adult=adult, description=short(desc, 280), sources=[page_url],
        ))
    return out


# --------------------------------------------------------------------------------------
# Freitext (ohne KI): einfache Erkennung rund um das Stichwort
# --------------------------------------------------------------------------------------

def page_text(soup: BeautifulSoup) -> str:
    for t in soup(["script", "style", "noscript", "svg", "nav", "footer", "header", "form", "iframe"]):
        t.decompose()
    text = soup.get_text("\n")
    lines = [clean_ws(l) for l in text.splitlines()]
    return "\n".join(l for l in lines if l)


def site_name(soup: BeautifulSoup, url: str) -> str:
    og = soup.find("meta", property="og:site_name")
    if og and og.get("content"):
        return clean_ws(og["content"])
    title = clean_ws(soup.title.get_text()) if soup.title else ""
    if title:
        parts = re.split(r"\s+[|–—-]\s+", title)
        # meist steht der Name der Einrichtung im letzten Teil ("Termine | Gymnasium XY")
        cand = [p for p in parts if not _KW_RE.search(p)]
        if cand:
            return cand[-1][:90]
        return parts[-1][:90]
    return urlparse(url).netloc.removeprefix("www.")


_INSTITUTION = re.compile(
    r"schule|gymnasium|kolleg|universit|hochschule|akademie|campus|institut|museum|feuerwehr|polizei|"
    r"rathaus|gmbh|\bag\b|werk|zentrum|betrieb|kaserne|bundeswehr|klinik|verwaltung|amt\b", re.I)


def _looks_like_name(line: str) -> bool:
    return (3 <= len(line) <= 90 and not _KW_RE.search(line) and not find_dates(line)
            and not re.search(r"\buhr\b|anmeld|siehe|www\.|http|@", line, re.I)
            and bool(re.match(r"[A-ZÄÖÜ0-9]", line)))


def events_from_text(text: str, site: str, page_url: str, hint: str | None, title: str) -> list[Event]:
    """Einfache Erkennung ohne KI.

    Arbeitet zeilenweise, weil Terminlisten meist so aufgebaut sind:
        Name der Einrichtung / Art der Veranstaltung / Datum, Uhrzeit
    Ein Datum VOR dem Stichwort gehört fast immer zum vorigen Eintrag und wird ignoriert.
    """
    out: list[Event] = []
    seen: set[tuple[str, dt.date]] = set()
    lines = [l for l in text.split("\n") if l.strip()]
    page_addr, page_city = find_address(text)
    horizon = TODAY + dt.timedelta(days=HORIZON_DAYS)
    kw_lines = [i for i, l in enumerate(lines) if _KW_RE.search(l)]

    def starts_with_date(l: str) -> bool:
        return bool(re.match(r"\s*(?:[A-Za-zÄÖÜäöü]{2,10}\.?,?\s+)?\d{1,2}\.", l))

    def name_then_date(l: str) -> bool:
        ds = find_dates(l)
        return bool(ds) and len(re.findall(r"[A-Za-zÄÖÜäöüß]", l[: ds[0][0]])) >= 4

    def after_chunk(i: int) -> list[str]:
        # Datum im Rest der Zeile oder in einer der nächsten zwei Zeilen, die MIT dem Datum beginnt
        m = _KW_RE.search(lines[i])
        chunk = [lines[i][m.start():]]
        for nxt in lines[i + 1: i + 3]:
            if _KW_RE.search(nxt) or (find_dates(nxt) and not starts_with_date(nxt)):
                break
            chunk.append(nxt)
        return chunk

    def before_chunk(i: int) -> list[str]:
        # Tabellenzeile davor: "Name  Datum" (Datum steht HINTER einem Namen)
        chunk: list[str] = []
        for prev in reversed(lines[max(0, i - 3): i]):
            if _KW_RE.search(prev):
                break
            chunk.insert(0, prev)
            if find_dates(prev):
                return chunk if name_then_date(prev) else []
        return []

    # Aufbau der Seite erkennen: steht das Datum meist NACH dem Stichwort (Name / Art / Datum)
    # oder DAVOR (Tabellen: Name Datum / Uhrzeit / Art)?
    n_after = sum(1 for i in kw_lines if find_dates("\n".join(after_chunk(i))))
    n_before = sum(1 for i in kw_lines if find_dates("\n".join(before_chunk(i))))
    date_first = n_before > n_after

    for i in kw_lines:
        line = lines[i]
        m = _KW_RE.search(line)
        chunk = before_chunk(i) if date_first else after_chunk(i)
        chunk_text = "\n".join(chunk)
        dates = [d for _, d in find_dates(chunk_text) if TODAY <= d <= horizon]
        if not dates:
            continue
        d = dates[0]
        multi = [x for x in dates[1:3] if 0 < (x - d).days <= 5]
        st, et = find_times(chunk_text)
        org = ""
        if date_first:
            # Name steht in der Zeile mit dem Datum (Kürzel wie "GY", "RS" und das Datum entfernen)
            date_line = next((c for c in chunk if find_dates(c)), "")
            cand = re.sub(r"\b\d{1,2}\.\d{1,2}\.\d{2,4}\b.*$", "", date_line)
            cand = re.sub(r"^\s*(?:[A-ZÄÖÜ]{1,4}\s+)+(?=[A-ZÄÖÜ][a-zäöüß])", "", cand).strip(" -–,:")
            if len(cand) >= 4:
                org = cand
            else:
                idx = i - len(chunk) - 1
                if idx >= 0 and _looks_like_name(lines[idx]):
                    org = lines[idx]
        else:
            # Einrichtung: steht die Zeile allein, ist die Zeile davor meist der Name
            rest = clean_ws(_KW_RE.sub("", line[: m.start()] + line[m.end():]))
            rest = re.sub(r"^[\s:,–\-/|]+|[\s:,–\-/|]+$", "", rest)
            if rest and _INSTITUTION.search(rest) and not find_dates(rest) and len(rest) <= 90:
                org = re.sub(r"^(?:am|an der|im|in der|des|der)\s+", "", rest, flags=re.I)
            else:
                # rückwärts bis zu 5 Zeilen: erste Zeile, die wie ein Einrichtungsname aussieht
                for prev in reversed(lines[max(0, i - 5): i]):
                    if _looks_like_name(prev) and _INSTITUTION.search(prev):
                        org = prev
                        break
        org = (org or site).rstrip(":;,–- ").strip()
        if _ONLINE.search(line + " " + chunk_text):
            continue                                   # Online-Termine kann man nicht besuchen
        if (org, d) in seen:
            continue
        seen.add((org, d))
        ctx = "\n".join(lines[max(0, i - 2): i + 4])
        min_age, pro, adult = age_info(ctx)
        if pro or not bundeswehr_ok(ctx, min_age):
            continue
        addr, city = find_address(ctx)
        if not addr and org == site:
            addr, city = page_addr, page_city
        if not city and page_city:
            city = page_city
        if not addr and city:
            addr = f"{org}, {city}" if org != site else city
        kw = m.group(0)
        label = kw[:1].upper() + kw[1:]
        out.append(Event(
            title=label, org=org, category=classify(org, line, title, hint=hint), date=d,
            end_date=multi[-1] if multi else None, start_time=st, end_time=et,
            address=addr, city=city, url=page_url, min_age=min_age, needs_adult=adult,
            description=short(" · ".join(chunk), 200), sources=[page_url],
        ))
    # Auf Sammelseiten (viele Einträge) ist ein Termin ohne erkannte Einrichtung nicht zuzuordnen.
    if len(out) >= 3:
        out = [e for e in out if e.org != site]
    return out


_ONLINE = re.compile(r"\b(online|videochat|video-chat|webinar|livestream|virtuell|digital(?:er|e)?\s+(?:tag|infotag))\b", re.I)


def event_from_headline(head: str, page_title: str, text: str, page_url: str, hint: str | None,
                        site: str) -> Event | None:
    """Einzelseite über genau eine Veranstaltung (z. B. eine Messe): Überschrift = Name."""
    if not head or not _KW_RE.search(head + " " + page_title) or len(head) > 120:
        return None
    pos = text.find(head)
    window = text[pos: pos + 1500] if pos >= 0 else text[:1500]
    horizon = TODAY + dt.timedelta(days=HORIZON_DAYS)
    # Daten, neben denen "online" steht (Begleitprogramm im Netz), zählen nicht
    dates = [d for p, d in find_dates(window)
             if TODAY <= d <= horizon and not _ONLINE.search(window[max(0, p - 70): p + 70])]
    if not dates or _ONLINE.search(head):
        return None
    d = dates[0]
    multi = [x for x in dates[1:3] if 0 < (x - d).days <= 5]
    st, et = find_times(window)
    addr, city = find_address(window)
    min_age, pro, adult = age_info(window)
    if pro or not bundeswehr_ok(window, min_age):
        return None
    cat = classify(head, window[:300], hint=hint)
    kind = {"ausbildung": "Ausbildungsmesse", "hochschule": "Hochschulinformationstag"}.get(cat, "Tag der offenen Tür")
    m = _KW_RE.search(head)
    if m and cat not in ("ausbildung", "hochschule"):
        kind = m.group(0)[:1].upper() + m.group(0)[1:]
    # Name der Einrichtung = Überschrift ohne das Stichwort ("Tag der offenen Tür im X" -> "X");
    # bleibt kaum etwas übrig, ist es eine allgemeine Überschrift -> Name der Website
    org = head
    if m and cat != "ausbildung":
        rest = clean_ws(head[: m.start()] + " " + head[m.end():])
        rest = re.sub(r"^(?:e|n|en)?\s*(?:im|am|an der|in der|der|des|bei der|beim|an|in)\s+", "", rest, flags=re.I)
        rest = re.sub(r"\b20\d\d\b", "", rest).strip(" -–:,|")
        org = rest if len(rest) >= 6 else site
    return Event(
        title=kind, org=org, category=cat, date=d, end_date=multi[-1] if multi else None,
        start_time=st, end_time=et, address=addr, city=city, url=page_url,
        min_age=min_age, needs_adult=adult, description=short(window[len(head):].replace("\n", " "), 220),
        sources=[page_url],
    )


# --------------------------------------------------------------------------------------
# KI-Auswertung mit Claude (optional, nur mit ANTHROPIC_API_KEY)
# --------------------------------------------------------------------------------------

LLM_MODEL = os.environ.get("LLM_MODEL", "claude-opus-5-5")

LLM_SYSTEM = f"""Du liest deutsche Webseiten und ziehst Termine für "Tage der offenen Tür" und ähnliche
öffentliche Info-Veranstaltungen heraus (Hochschulinformationstag, Schnupperstudium, Tag der offenen Tür
an Schulen, Ausbildungsmessen, Betriebsbesichtigungen, offene Tage bei Feuerwehr, Polizei, Rathaus,
Museen, Forschungsinstituten, Bundeswehr).
Heute ist der {TODAY.isoformat()}. Gib nur Termine zurück, die heute oder später stattfinden und in
Deutschland liegen. Erfinde nichts: Was nicht auf der Seite steht, bleibt leer ("" bzw. 0).
Regeln:
- category: "hochschule" (Unis, Hochschulen, Berufsakademien), "schule" (alle Schulformen inkl.
  Berufsschulen), "ausbildung" (Firmen, Ausbildungsmessen, Betriebe, Kammern), "sonstiges" (Behörden,
  Feuerwehr, Polizei, Museen, Forschung, Bundeswehr, alles andere).
- min_age: ausdrücklich genanntes Mindestalter, sonst 0. "unter 16 nur mit Begleitung" ist KEIN
  Mindestalter, sondern needs_adult = true.
- audience: "fachpublikum", wenn nur Fachbesucher, Mitarbeitende, geladene Gäste oder geschlossene
  Gruppen teilnehmen dürfen; "erwachsene" bei Veranstaltungen nur für Volljährige; sonst "alle",
  "schueler", "studieninteressierte" oder "familien".
- needs_adult: true, wenn Jugendliche eine erwachsene Begleitperson brauchen.
- Bundeswehr-Termine nur, wenn sie ausdrücklich öffentlich/für Familien sind oder ab 14 erlaubt sind.
- date/end_date als YYYY-MM-DD, start_time/end_time als HH:MM (24 h). Mehrtägig: end_date setzen.
- lat/lng nur, wenn sie auf der Seite stehen, sonst 0.
- description: ein bis zwei sachliche Sätze auf Deutsch, was man dort erleben kann.
Wenn die Seite keinen passenden Termin enthält, gib eine leere Liste zurück."""

LLM_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "events": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "org": {"type": "string"},
                    "category": {"type": "string", "enum": list(CATEGORIES)},
                    "date": {"type": "string"},
                    "end_date": {"type": "string"},
                    "start_time": {"type": "string"},
                    "end_time": {"type": "string"},
                    "address": {"type": "string"},
                    "city": {"type": "string"},
                    "lat": {"type": "number"},
                    "lng": {"type": "number"},
                    "url": {"type": "string"},
                    "min_age": {"type": "integer"},
                    "audience": {"type": "string",
                                 "enum": ["alle", "schueler", "studieninteressierte", "familien",
                                          "fachpublikum", "erwachsene"]},
                    "needs_adult": {"type": "boolean"},
                    "description": {"type": "string"},
                },
                "required": ["title", "org", "category", "date", "end_date", "start_time", "end_time",
                             "address", "city", "lat", "lng", "url", "min_age", "audience",
                             "needs_adult", "description"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["events"],
    "additionalProperties": False,
}

LLM_PAGE_CHARS = 60_000  # Webseiten-Text pro Anfrage; der relevante Teil steht praktisch immer davor


class Claude:
    """Dünne Hülle um das offizielle Anthropic-SDK."""

    def __init__(self) -> None:
        import anthropic
        self.anthropic = anthropic
        self.client = anthropic.Anthropic(max_retries=3)
        self.calls = 0
        self.disabled = False

    def _create(self, **kw: Any) -> Any:
        a = self.anthropic
        try:
            self.calls += 1
            return self.client.beta.messages.create(
                model=LLM_MODEL,
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                **kw,
            )
        except (a.AuthenticationError, a.PermissionDeniedError) as e:
            log(f"  Claude: Schlüssel ungültig oder ohne Berechtigung – KI wird abgeschaltet ({e})")
            self.disabled = True
        except a.BadRequestError as e:
            log(f"  Claude: Anfrage abgelehnt: {e}")
            if "credit" in str(e).lower() or "billing" in str(e).lower():
                self.disabled = True
        except a.RateLimitError:
            log("  Claude: Ratenlimit erreicht – KI für diesen Lauf abgeschaltet")
            self.disabled = True
        except a.APIStatusError as e:
            log(f"  Claude: Serverfehler {e.status_code}")
        except a.APIConnectionError:
            log("  Claude: keine Verbindung")
        return None

    def extract(self, text: str, url: str) -> list[dict[str, Any]]:
        if self.disabled:
            return []
        resp = self._create(
            max_tokens=16000,
            system=LLM_SYSTEM,
            output_config={"effort": "low", "format": {"type": "json_schema", "schema": LLM_SCHEMA}},
            messages=[{"role": "user", "content": f"Seite: {url}\n\n<seite>\n{text[:LLM_PAGE_CHARS]}\n</seite>"}],
        )
        if resp is None or resp.stop_reason in ("refusal", "max_tokens"):
            return []
        raw = "".join(b.text for b in resp.content if b.type == "text")
        try:
            return list(json.loads(raw).get("events", []))
        except json.JSONDecodeError:
            log(f"  Claude: kein gültiges JSON für {url}")
            return []

    def search(self, query: str) -> list[str]:
        """Websuche über das Claude-Werkzeug web_search; liefert nur die gefundenen Adressen."""
        if self.disabled:
            return []
        resp = self._create(
            max_tokens=4000,
            output_config={"effort": "low"},
            tools=[{"type": "web_search_20260209", "name": "web_search", "max_uses": 2,
                    "user_location": {"type": "approximate", "country": "DE", "timezone": "Europe/Berlin"}}],
            messages=[{"role": "user", "content":
                       f"Suche im Web nach offiziellen Seiten mit konkreten, kommenden Terminen: {query}. "
                       "Bevorzuge die Websites der Einrichtungen selbst und städtische Terminlisten. "
                       "Antworte danach nur mit dem Wort 'fertig'."}],
        )
        urls: list[str] = []
        if resp is None:
            return urls
        for block in resp.content:
            if getattr(block, "type", "") == "web_search_tool_result" and isinstance(block.content, list):
                for r in block.content:
                    u = getattr(r, "url", None)
                    if u:
                        urls.append(u)
        return urls


def events_from_llm(items: list[dict[str, Any]], page_url: str, hint: str | None) -> list[Event]:
    out: list[Event] = []
    for it in items:
        try:
            d = dt.date.fromisoformat(it["date"])
        except (KeyError, ValueError):
            continue
        ed = None
        if it.get("end_date"):
            try:
                ed = dt.date.fromisoformat(it["end_date"])
            except ValueError:
                ed = None
        audience = it.get("audience") or "alle"
        if audience == "fachpublikum":
            continue
        min_age = int(it.get("min_age") or 0) or None
        if audience == "erwachsene":
            min_age = max(min_age or 0, 18)
        text = " ".join(str(it.get(k, "")) for k in ("title", "org", "description"))
        if not bundeswehr_ok(text, min_age) and audience not in ("alle", "familien"):
            continue
        lat, lng = it.get("lat") or None, it.get("lng") or None
        st = it.get("start_time") or ""
        et = it.get("end_time") or ""
        if st and not re.fullmatch(r"\d{2}:\d{2}", st):
            st = ""
        if et and not re.fullmatch(r"\d{2}:\d{2}", et):
            et = ""
        out.append(Event(
            title=clean_ws(it.get("title")) or "Tag der offenen Tür", org=clean_ws(it.get("org")),
            category=it.get("category") if it.get("category") in CATEGORIES else classify(text, hint=hint),
            date=d, end_date=ed if ed and ed != d else None, start_time=st, end_time=et,
            address=clean_ws(it.get("address")), city=clean_ws(it.get("city")),
            lat=float(lat) if lat else None, lng=float(lng) if lng else None,
            url=urljoin(page_url, it.get("url") or page_url), min_age=min_age, audience=audience,
            needs_adult=bool(it.get("needs_adult")), description=short(it.get("description", ""), 280),
            sources=[page_url],
        ))
    return out


# --------------------------------------------------------------------------------------
# Geocoding mit OpenStreetMap Nominatim (max. 1 Anfrage/Sekunde, mit Zwischenspeicher)
# --------------------------------------------------------------------------------------

class Geocoder:
    URL = "https://nominatim.openstreetmap.org/search"

    def __init__(self, session: requests.Session, max_requests: int):
        self.s = session
        self.cache: dict[str, list[float] | None] = {}
        if GEOCACHE_FILE.exists():
            self.cache = json.loads(GEOCACHE_FILE.read_text("utf-8"))
        self.budget = max_requests
        self.last = 0.0

    def lookup(self, query: str) -> tuple[float, float, str] | None:
        q = clean_ws(query)
        if not q:
            return None
        if q in self.cache:
            v = self.cache[q]
            return (v[0], v[1], v[2] if len(v) > 2 else "") if v else None
        if self.budget <= 0:
            return None
        self.budget -= 1
        wait = self.last + 1.1 - time.time()
        if wait > 0:
            time.sleep(wait)
        self.last = time.time()
        try:
            r = self.s.get(self.URL, params={"q": q, "format": "jsonv2", "limit": 1, "countrycodes": "de",
                                             "addressdetails": 1, "accept-language": "de"},
                           timeout=HTTP_TIMEOUT)
            res = r.json() if r.ok else []
        except (requests.RequestException, ValueError):
            return None
        if res:
            lat, lng = float(res[0]["lat"]), float(res[0]["lon"])
            a = res[0].get("address", {})
            city = a.get("city") or a.get("town") or a.get("village") or a.get("municipality") or ""
            if in_germany(lat, lng):
                self.cache[q] = [lat, lng, city]
                return lat, lng, city
        self.cache[q] = None
        return None

    def save(self) -> None:
        GEOCACHE_FILE.write_text(json.dumps(self.cache, ensure_ascii=False, indent=0, sort_keys=True), "utf-8")


def geocode(e: Event, geo: Geocoder) -> None:
    if in_germany(e.lat, e.lng):
        return
    e.lat = e.lng = None
    queries = []
    if e.address:
        queries.append(e.address)
    if e.org and e.city:
        queries.append(f"{e.org}, {e.city}")
    if e.org and not e.city and _INSTITUTION.search(e.org):
        queries.append(e.org)
    if e.city:
        queries.append(e.city)
    for q in queries:
        hit = geo.lookup(q)
        if hit:
            e.lat, e.lng, found_city = hit
            if not e.city:
                e.city = found_city or find_address(e.address)[1]
            return


# --------------------------------------------------------------------------------------
# Zusammenführen
# --------------------------------------------------------------------------------------

def _similar(a: str, b: str) -> float:
    a, b = norm(a), norm(b)
    if not a or not b:
        return 0.0
    if a in b or b in a:
        return 0.95
    return difflib.SequenceMatcher(None, a, b).ratio()


def same_event(a: Event, b: Event) -> bool:
    if a.date != b.date:
        return False
    name_sim = max(_similar(a.org, b.org), _similar(a.title, b.title))
    if a.lat is not None and b.lat is not None:
        dist = haversine_km((a.lat, a.lng), (b.lat, b.lng))
        return (dist < 0.4 and name_sim > 0.75) or (dist < 3 and name_sim > 0.88)
    return name_sim > 0.85 and (not a.city or not b.city or norm(a.city) == norm(b.city))


def merge_into(base: Event, other: Event) -> None:
    for f in ("org", "address", "city", "start_time", "end_time", "url", "description"):
        if not getattr(base, f) and getattr(other, f):
            setattr(base, f, getattr(other, f))
    if len(other.description) > len(base.description) and not base.manual:
        base.description = other.description
    if base.lat is None and other.lat is not None:
        base.lat, base.lng = other.lat, other.lng
    if base.end_date is None and other.end_date:
        base.end_date = other.end_date
    if other.min_age is not None:
        base.min_age = max(base.min_age or 0, other.min_age)
    base.needs_adult = base.needs_adult or other.needs_adult
    base.manual = base.manual or other.manual
    for s in other.sources:
        if s not in base.sources:
            base.sources.append(s)
    base.first_seen = min(x for x in (base.first_seen, other.first_seen) if x) if (base.first_seen or other.first_seen) else ""
    base.last_seen = max(base.last_seen, other.last_seen)


def dedupe(events: list[Event]) -> list[Event]:
    out: list[Event] = []
    by_date: dict[dt.date, list[Event]] = {}
    # handgeprüfte Einträge zuerst, damit ihre Angaben gewinnen
    for e in sorted(events, key=lambda x: (not x.manual, x.lat is None, -len(x.description))):
        bucket = by_date.setdefault(e.date, [])
        twin = next((b for b in bucket if same_event(b, e)), None)
        if twin:
            merge_into(twin, e)
        else:
            bucket.append(e)
            out.append(e)
    return out


# --------------------------------------------------------------------------------------
# Quellen verarbeiten
# --------------------------------------------------------------------------------------

def is_ics(url: str, resp: requests.Response) -> bool:
    ct = resp.headers.get("content-type", "").lower()
    return "text/calendar" in ct or url.lower().split("?")[0].endswith((".ics", ".ical"))


def is_pdf(url: str, resp: requests.Response) -> bool:
    ct = resp.headers.get("content-type", "").lower()
    return "application/pdf" in ct or url.lower().split("?")[0].endswith(".pdf")


def pdf_text(content: bytes) -> str:
    from pypdf import PdfReader
    try:
        reader = PdfReader(io.BytesIO(content))
        return "\n".join((p.extract_text() or "") for p in reader.pages[:30])
    except Exception:  # noqa: BLE001
        return ""


def interesting_links(soup: BeautifulSoup, base_url: str, limit: int, same_host: bool,
                      pattern: re.Pattern[str] | None = None) -> list[str]:
    host = urlparse(base_url).netloc
    out: list[str] = []
    for a in soup.find_all("a", href=True):
        href = urldefrag(urljoin(base_url, a["href"]))[0]
        if not href.startswith("http"):
            continue
        if same_host and urlparse(href).netloc != host:
            continue
        label = clean_ws(a.get_text(" ")) + " " + href.replace("-", " ").replace("_", " ")
        hit = pattern.search(href) if pattern else _KW_RE.search(label)
        if hit and href not in out and href != base_url:
            out.append(href)
        if len(out) >= limit:
            break
    return out


@dataclass
class Crawl:
    fetcher: PoliteFetcher
    claude: Claude | None
    max_pages: int
    max_llm_pages: int
    pages: int = 0
    llm_pages: int = 0
    visited: set[str] = field(default_factory=set)

    def process(self, url: str, hint: str | None, follow: int, same_host: bool, depth: int = 0,
                link_pattern: re.Pattern[str] | None = None) -> list[Event]:
        url = urldefrag(url)[0]
        if url in self.visited or self.pages >= self.max_pages:
            return []
        self.visited.add(url)
        self.pages += 1
        log(f"[{self.pages}] {url}")
        r = self.fetcher.get(url)
        if r is None:
            return []
        if is_ics(url, r):
            return events_from_ics(r.content, url, hint)

        h1_text = ""
        if is_pdf(url, r):
            text, soup, org, title = pdf_text(r.content), None, urlparse(url).netloc.removeprefix("www."), ""
        else:
            soup = BeautifulSoup(r.content, "html.parser")
            h1 = soup.find("h1")
            h1_text = clean_ws(h1.get_text(" ")) if h1 else ""
            found = events_from_jsonld(soup, url, hint, require_kw=True)
            org = site_name(soup, url)
            title = clean_ws(soup.title.get_text()) if soup.title else ""
            links = interesting_links(soup, url, follow, same_host, link_pattern) if follow and depth == 0 else []
            ics_links = [urljoin(url, a["href"]) for a in soup.find_all("a", href=True)
                         if a["href"].lower().split("?")[0].endswith(".ics")][:3] if depth == 0 else []
            text = page_text(soup)
            if found:
                return found + self._follow(links + ics_links, hint, same_host, depth)
        events: list[Event] = []
        has_kw = bool(_KW_RE.search(text))
        has_date = bool(find_dates(text))
        if has_kw and has_date:
            if self.claude and not self.claude.disabled and self.llm_pages < self.max_llm_pages:
                self.llm_pages += 1
                events = events_from_llm(self.claude.extract(text, url), url, hint)
                for e in events:
                    if not e.org:
                        e.org = org
            else:
                single = event_from_headline(h1_text, title, text, url, hint, org) if soup is not None else None
                events = [single] if single else events_from_text(text, org, url, hint, title)
        log(f"  -> {len(events)} Termin(e)")
        if soup is not None:
            events += self._follow(links + ics_links, hint, same_host, depth)
        return events

    def _follow(self, links: list[str], hint: str | None, same_host: bool, depth: int) -> list[Event]:
        out: list[Event] = []
        for link in links:
            out += self.process(link, hint, 0, same_host, depth + 1)
        return out


# --------------------------------------------------------------------------------------
# Suchanfragen (rotieren täglich, damit über die Zeit ganz Deutschland abgedeckt wird)
# --------------------------------------------------------------------------------------

CITIES = [
    "Berlin", "Hamburg", "München", "Köln", "Frankfurt am Main", "Stuttgart", "Düsseldorf", "Leipzig",
    "Dortmund", "Essen", "Bremen", "Dresden", "Hannover", "Nürnberg", "Duisburg", "Bochum", "Wuppertal",
    "Bielefeld", "Bonn", "Münster", "Mannheim", "Karlsruhe", "Augsburg", "Wiesbaden", "Mönchengladbach",
    "Gelsenkirchen", "Aachen", "Braunschweig", "Kiel", "Chemnitz", "Halle (Saale)", "Magdeburg",
    "Freiburg im Breisgau", "Krefeld", "Mainz", "Lübeck", "Erfurt", "Oberhausen", "Rostock", "Kassel",
    "Hagen", "Potsdam", "Saarbrücken", "Hamm", "Ludwigshafen", "Oldenburg", "Mülheim an der Ruhr",
    "Osnabrück", "Leverkusen", "Heidelberg", "Darmstadt", "Solingen", "Regensburg", "Herne", "Paderborn",
    "Neuss", "Ingolstadt", "Offenbach", "Fürth", "Würzburg", "Ulm", "Heilbronn", "Pforzheim", "Wolfsburg",
    "Göttingen", "Bottrop", "Reutlingen", "Koblenz", "Bremerhaven", "Recklinghausen", "Erlangen",
    "Bergisch Gladbach", "Remscheid", "Jena", "Trier", "Salzgitter", "Moers", "Siegen", "Hildesheim",
    "Cottbus", "Schwerin", "Gera", "Zwickau", "Flensburg", "Greifswald", "Passau", "Bamberg", "Bayreuth",
    "Konstanz", "Tübingen", "Lüneburg", "Gießen", "Marburg", "Fulda", "Weimar", "Frankfurt (Oder)",
]
TOPICS = [
    "Tag der offenen Tür Gymnasium {city} {month}",
    "Tag der offenen Tür Schule {city} {year}",
    "Hochschulinformationstag Schnupperstudium {city} {year}",
    "Ausbildungsmesse {city} {year} Schüler",
    "Tag der offenen Tür Feuerwehr Polizei Rathaus {city} {year}",
    "Tag der offenen Tür Museum Forschungsinstitut {city} {year}",
    "Betriebsbesichtigung Tag der offenen Tür Unternehmen Ausbildung {city} {year}",
]
MONTH_NAMES = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September",
               "Oktober", "November", "Dezember"]


def todays_queries(n: int) -> list[str]:
    day = TODAY.toordinal()
    out = []
    for i in range(n):
        city = CITIES[(day * n + i) % len(CITIES)]
        topic = TOPICS[(day + i) % len(TOPICS)]
        month_date = TODAY + dt.timedelta(days=30 * (i % 4))
        out.append(topic.format(city=city, month=f"{MONTH_NAMES[month_date.month - 1]} {month_date.year}",
                                year=month_date.year))
    return out


# --------------------------------------------------------------------------------------
# Hauptprogramm
# --------------------------------------------------------------------------------------

def load_yaml(path: Path) -> Any:
    if not path.exists():
        return None
    return yaml.safe_load(path.read_text("utf-8"))


def manual_events() -> list[Event]:
    raw = load_yaml(MANUAL_FILE) or []
    out = []
    for it in raw:
        try:
            d = it["date"] if isinstance(it["date"], dt.date) else dt.date.fromisoformat(str(it["date"]))
        except (KeyError, ValueError):
            log(f"  manual_events.yaml: Datum fehlt/ungültig bei {it.get('title')}")
            continue
        ed = it.get("end_date")
        if ed and not isinstance(ed, dt.date):
            ed = dt.date.fromisoformat(str(ed))
        e = Event(
            title=it.get("title", "Tag der offenen Tür"), org=it.get("org", ""),
            category=it.get("category") if it.get("category") in CATEGORIES else classify(it.get("title", ""), it.get("org", "")),
            date=d, end_date=ed, start_time=str(it.get("start_time", "") or ""), end_time=str(it.get("end_time", "") or ""),
            address=it.get("address", ""), city=it.get("city", ""), lat=it.get("lat"), lng=it.get("lng"),
            url=it.get("url", ""), min_age=it.get("min_age"), audience=it.get("audience", "alle"),
            needs_adult=bool(it.get("needs_adult", False)), description=it.get("description", ""),
            sources=[it.get("source") or it.get("url", "")], manual=True,
        )
        out.append(e)
    return out


def previous_events() -> list[Event]:
    if not EVENTS_FILE.exists():
        return []
    try:
        data = json.loads(EVENTS_FILE.read_text("utf-8"))
        return [Event.from_json(d) for d in data.get("events", [])]
    except (json.JSONDecodeError, KeyError, ValueError) as e:
        log(f"Alte events.json unlesbar ({e}) – fange neu an")
        return []


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-llm", action="store_true", help="Claude nicht benutzen")
    ap.add_argument("--no-search", action="store_true", help="keine Websuche")
    ap.add_argument("--only", action="append", help="nur diese URL(s) verarbeiten (zum Testen)")
    ap.add_argument("--max-pages", type=int, default=int(os.environ.get("MAX_PAGES", 400)))
    ap.add_argument("--max-llm-pages", type=int, default=int(os.environ.get("MAX_LLM_PAGES", 40)))
    ap.add_argument("--search-queries", type=int, default=int(os.environ.get("SEARCH_QUERIES", 8)))
    ap.add_argument("--max-geocode", type=int, default=int(os.environ.get("MAX_GEOCODE", 250)))
    ap.add_argument("--dry-run", action="store_true", help="nichts speichern, nur ausgeben")
    ap.add_argument("--out", type=Path, help="Ergebnis in diese Datei statt data/events.json (zum Testen)")
    args = ap.parse_args()

    DATA_DIR.mkdir(exist_ok=True)
    cfg = load_yaml(SOURCES_FILE) or {}
    fetcher = PoliteFetcher(cfg.get("blocked_domains", []))

    claude: Claude | None = None
    if not args.no_llm and os.environ.get("ANTHROPIC_API_KEY"):
        try:
            claude = Claude()
            log(f"KI-Auswertung an ({LLM_MODEL})")
        except ImportError:
            log("Paket 'anthropic' fehlt – KI-Auswertung aus")
    else:
        log("KI-Auswertung aus (kein ANTHROPIC_API_KEY) – nutze strukturierte Daten und Text-Erkennung")

    crawl = Crawl(fetcher, claude, args.max_pages, args.max_llm_pages)
    found: list[Event] = []

    if args.only:
        for u in args.only:
            found += crawl.process(u, None, follow=15, same_host=True)
    else:
        for src in cfg.get("sources", []):
            pat = re.compile(src["link_pattern"], re.I) if src.get("link_pattern") else None
            found += crawl.process(src["url"], src.get("category"), follow=int(src.get("follow", 0)),
                                   same_host=bool(src.get("same_host", True)), link_pattern=pat)
        if claude and not args.no_search:
            for q in todays_queries(args.search_queries):
                log(f"Suche: {q}")
                for u in claude.search(q)[:6]:
                    found += crawl.process(u, None, follow=4, same_host=True)

    stamp = NOW.isoformat(timespec="seconds")
    for e in found:
        e.first_seen = e.first_seen or stamp
        e.last_seen = stamp
    manual = manual_events()
    for e in manual:
        e.first_seen = e.first_seen or stamp
        e.last_seen = stamp

    if args.only:
        merged_input = manual + found
    else:
        old = previous_events()
        forget = (NOW - dt.timedelta(days=FORGET_AFTER_DAYS)).isoformat()
        old = [e for e in old if (e.last_seen or "") >= forget and not e.manual]
        merged_input = manual + found + old

    # Aufräumen
    cleaned: list[Event] = []
    for e in merged_input:
        if e.end_dt() < NOW or e.date > TODAY + dt.timedelta(days=HORIZON_DAYS):
            continue
        if e.audience == "fachpublikum":
            continue
        e.title = short(e.title, 120)
        e.org = short(e.org, 100)
        cleaned.append(e)

    geo = Geocoder(fetcher.s, args.max_geocode)
    for e in cleaned:
        geocode(e, geo)
    events = dedupe(cleaned)
    events.sort(key=lambda e: (e.start_dt(), e.org))

    payload = {
        "version": 1,
        "generated": stamp,
        "count": len(events),
        "ageRule": "Fachpublikum ausgeblendet; minAge = Mindestalter laut Quelle (App filtert nach eigenem Alter)",
        "events": [e.to_json() for e in events],
    }
    log(f"\nFertig: {len(events)} Termine | Seiten: {fetcher.stats} | KI-Aufrufe: {claude.calls if claude else 0}")
    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    target = args.out or EVENTS_FILE
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=1), "utf-8")
    geo.save()
    log(f"Gespeichert: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
