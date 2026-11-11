"""Kurze Übersicht über eine events.json (zum Prüfen nach einem Lauf)."""
import json
import sys
from collections import Counter

path = sys.argv[1] if len(sys.argv) > 1 else "data/events.json"
with open(path, encoding="utf-8") as f:
    data = json.load(f)
events = data["events"]
print(f"{len(events)} Termine, erzeugt {data['generated']}")
print("Kategorien:", dict(Counter(e["category"] for e in events)))
print("ohne Koordinaten:", sum(1 for e in events if e["lat"] is None))
for e in events:
    flags = ("A" if e["needsAdult"] else "-") + (f"{e['minAge']}+" if e["minAge"] else "")
    print(f"{e['start'][:16]} {e['category'][:5]:5} {flags:4} {e['org'][:45]:45} | {e['title'][:30]:30} | {e['city'][:18]:18} | {e['lat']}")
