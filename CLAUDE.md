# Ironline (Godot 4.7, GDScript)

Arcade-Multiplayer-FPS. Phasen 1-8 fertig (siehe README.md), offen: 9 Windows-Build und Abschlusstests.
Architektur: docs/ARCHITECTURE.md (nur bei Bedarf lesen). Sprache: Deutsch.

## Arbeitsregeln
- Nur die für die Aufgabe relevanten Dateien lesen; keine Projektanalyse, keine Agents/Parallelaufgaben ohne Auftrag.
- Bestehenden Code und Verhalten erhalten. Minimal-invasiv ändern, keine unnötigen Refactorings.
- Größere Aufgaben: zuerst kurzer Plan (wenige Zeilen), dann umsetzen.
- Antworten kurz und sachlich. Keine Platzhalter als funktionierend ausgeben.
- Keine kostenpflichtigen Dienste oder APIs, keine Fremd-Assets (alles prozedural/lizenzfrei).

## Prüfen (gezielt, nur was die Änderung betrifft)
- Statisch: `python3 tools/validate_project.py`
- Godot (Linux headless muss ggf. nachgeladen werden): `godot --headless --path . --import --quit`
  (nötig bei neuen `class_name`), dann `godot --headless --path . tests/smoke_test.tscn` (~30 s, Offline-Match, Maps, Bots).
- Netzwerk: `python3 tools/run_net_test.py <godot>` (Szenarien: Host+Client, Client verlässt Match, 3 Spieler; ~2 min). Nur bei Netzwerk-/Spieler-/Waffenänderungen.

## Git
- Es gibt nur `main` (laufend aktualisierter Teststand, direkt dort committen und pushen) und `sicherheitskopie` (fester Rückfallpunkt: nie ändern). Keine weiteren Branches anlegen.
- Nach jeder abgeschlossenen Phase lauffähigen Stand committen und pushen, README/Doku aktuell halten.
- Commits enden mit der vom System vorgegebenen Co-Authored-By-Zeile.

## GDScript-Fallen
- Lambdas capturen per Wert (Zähler in Dictionary legen).
- Nav-Map erst nach `BlockMap.wait_navigation_ready()` abfragbar.
- Server-/Authority-Logik nur über `MatchManager.is_authority()` / `NetworkManager.is_host()`; Schaden und Kills nie clientseitig.
