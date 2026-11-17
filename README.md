# Ironline – Arcade Multiplayer FPS (Godot 4)

Schneller First-Person-Arena-Shooter im Stil der klassischen Konsolen-Multiplayer-Ära:
drei Klassen, drei Drei-Wege-Maps, Team Deathmatch und Free for All, Bots und Online-Multiplayer.

## Aktueller Stand (Phase 1–5 abgeschlossen)

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Projektstruktur, First-Person-Controller, Testarena | fertig |
| 2 | AK-47, MP5, Shotgun, Pistole, Granate, Hitscan, Schaden, Tod | fertig |
| 3 | Team Deathmatch, Free for All, Respawn, Killlimit, Scoreboard, HUD | fertig |
| 4 | Maps Harbor, Frontier, Suburb, Bot-Navigation | fertig |
| 5 | Bot-KI | fertig |
| 6 | Online-Multiplayer | offen (Architektur ist serverautoritativ vorbereitet) |
| 7 | Lobby, Map-Voting, Menü-Polish | offen (Quick-Play-Menü vorhanden) |
| 8 | Polish | offen |
| 9 | Windows-Build, Tests | offen |

## Starten

1. [Godot 4.4 oder neuer](https://godotengine.org/download) installieren (Standard-Build, kein .NET nötig).
2. Godot starten, „Importieren“ → diesen Ordner (`project.godot`) auswählen.
3. Beim ersten Öffnen importiert Godot Texturen und Sounds (ca. 10 Sekunden).
4. F5 (Projekt starten) → Hauptmenü → **Multiplayer** → Modus, Klasse, Bots wählen → **Match starten**.

Steuerung: WASD bewegen, Maus zielen, Shift sprinten, Strg/C ducken, Leertaste springen,
LMT schießen, RMT zielen (ADS), R nachladen, Q / 1 / 2 Waffe wechseln, G Granate, Tab Scoreboard, Esc Pause.

## Prüfen

Ohne Godot (statische Prüfung von Pfaden, Szenen-Referenzen, Klammern, Typen):

```bash
py -3 tools/validate_project.py
```

Mit Godot (lädt alle Skripte/Szenen headless, simuliert ein kurzes Match mit Bewegung, Schuss,
Nachladen, Waffenwechsel, Granate, Kill, Respawn und Matchende, prüft alle vier Maps samt Nav-Mesh
und lässt 40 Sekunden lang schwere Bots gegeneinander spielen):

```bash
godot --headless --path . --import --quit
```

```bash
godot --headless --path . tests/smoke_test.tscn
```

Der Import-Schritt ist nur nötig, wenn das Projekt noch nie im Editor geöffnet wurde oder neue
Skripte mit `class_name` hinzukamen (der Editor erledigt das sonst automatisch). Der Test dauert
etwa 30 Sekunden und endet mit `OK: … keine Fehler.`

## Assets neu erzeugen

Alle Texturen und Sounds sind prozedural erzeugt (keine Fremdinhalte):

```bash
py -3 tools/generate_textures.py
```

```bash
py -3 tools/generate_audio.py
```

```bash
py -3 tools/generate_materials.py
```

## Struktur

Siehe [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) für die technischen Entscheidungen.

```
assets/        Texturen, Materialien, Audio
resources/     WeaponData-, ClassData-Ressourcen, Audio-Bus-Layout
scenes/        Szenen (Spieler, Waffenmodelle, Effekte, Maps, Game, Menüs)
scripts/       GDScript nach Verantwortung getrennt (player, weapons, gamemodes, systems, ui, maps, bots)
tools/         Python-Generatoren und Validator
tests/         Headless-Smoke-Test
```
