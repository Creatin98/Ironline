# Ironline – Arcade Multiplayer FPS (Godot 4)

Schneller First-Person-Arena-Shooter im Stil der klassischen Konsolen-Multiplayer-Ära:
drei Klassen, drei Drei-Wege-Maps, Team Deathmatch und Free for All, Bots und Online-Multiplayer.

## Aktueller Stand (Phase 1–7 abgeschlossen)

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Projektstruktur, First-Person-Controller, Testarena | fertig |
| 2 | AK-47, MP5, Shotgun, Pistole, Granate, Hitscan, Schaden, Tod | fertig |
| 3 | Team Deathmatch, Free for All, Respawn, Killlimit, Scoreboard, HUD | fertig |
| 4 | Maps Harbor, Frontier, Suburb, Bot-Navigation | fertig |
| 5 | Bot-KI | fertig |
| 6 | Online-Multiplayer (ENet, Host spielt mit, serverautoritativ) | fertig |
| 7 | Lobby (Team/Klasse/Bots), Map-Voting nach jeder Runde | fertig |
| 8 | Polish | offen |
| 9 | Windows-Build, Tests | offen |

## Starten

1. [Godot 4.4 oder neuer](https://godotengine.org/download) installieren (Standard-Build, kein .NET nötig).
2. Godot starten, „Importieren“ → diesen Ordner (`project.godot`) auswählen.
3. Beim ersten Öffnen importiert Godot Texturen und Sounds (ca. 10 Sekunden).
4. F5 (Projekt starten) → Hauptmenü:
   * **Training (Offline)**: Modus, Klasse, Bots wählen → **Match starten**.
   * **Online**: siehe „Online spielen“.

Steuerung: WASD bewegen, Maus zielen, Shift sprinten, Strg/C ducken, Leertaste springen,
LMT schießen, RMT zielen (ADS), R nachladen, Q / 1 / 2 Waffe wechseln, G Granate, Tab Scoreboard, Esc Pause.

## Online spielen

Ein Spieler ist Host (Server und Mitspieler zugleich), die anderen treten bei.

1. Host: **Online** → Port prüfen (Standard 7777) → **Hosten**. Die Lobby zeigt die IP-Adressen des Rechners.
2. Mitspieler: **Online** → IP-Adresse des Hosts und Port eintragen → **Beitreten**.
3. Jeder wählt in der Lobby Team (nur Team Deathmatch) und Klasse. Der Host stellt Modus, Map und Bots ein und startet das Match.
4. Die Klasse kann jederzeit gewechselt werden (Lobby, Pausemenü, Endbildschirm) und gilt ab dem nächsten Respawn.
5. Nach dem Match stimmen alle 15 Sekunden über die nächste Karte ab (Harbor, Frontier, Suburb). Bei Gleichstand oder ohne Stimmen entscheidet der Zufall, sobald alle gewählt haben startet die Runde sofort. Der Host kann stattdessen **Zur Lobby** wählen. Offline wählst du die nächste Karte direkt im Endbildschirm.

Im selben WLAN/LAN genügt die lokale IP des Hosts (z. B. `192.168.x.x`). Über das Internet muss der Host
den **UDP**-Port am Router an seinen Rechner weiterleiten (Port-Forwarding) und die öffentliche IP weitergeben;
eventuell muss die Windows-Firewall Godot für private/öffentliche Netzwerke erlauben. Bis zu 12 Spieler (TDM) bzw. 8 (FFA),
freie Plätze füllen Bots (serverseitig).

Zum Testen auf einem Rechner: zwei Spiel-Instanzen starten, eine hostet, die andere tritt mit `127.0.0.1` bei.

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

Netzwerktest (startet Host und Client als zwei Godot-Prozesse auf localhost und prüft Lobby, Matchstart,
Bewegung, Serverkorrektur, Treffer, Kill/Respawn, Granaten, Map-Voting und Host-Abschied; ca. 60 s):

```bash
py -3 tools/run_net_test.py "C:\Pfad\zu\godot.exe"
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
