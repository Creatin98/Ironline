# Ironline – Arcade Multiplayer FPS (Godot 4)

Schneller First-Person-Arena-Shooter im Stil der klassischen Konsolen-Multiplayer-Ära:
vier Klassen, drei Drei-Wege-Maps, Team Deathmatch und Free for All, Bots und Online-Multiplayer.

## Aktueller Stand (Phase 1–8 abgeschlossen)

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Projektstruktur, First-Person-Controller, Testarena | fertig |
| 2 | AK-47, MP5, Shotgun, Sniper, Pistole, Granate, Blendgranate, Hitscan, Schaden, Tod | fertig |
| 3 | Team Deathmatch, Free for All, Respawn, Killlimit, Scoreboard, HUD | fertig |
| 4 | Maps Harbor, Frontier, Suburb, Mesa, Bot-Navigation | fertig |
| 5 | Bot-KI | fertig |
| 6 | Online-Multiplayer (ENet, Host spielt mit, serverautoritativ) | fertig |
| 7 | Lobby (Team/Klasse/Bots), Map-Voting nach jeder Runde | fertig |
| 8 | Polish: Schadensrichtung, Mündungsfeuer/Körperanimation anderer Spieler, Effekt-Limit | fertig |
| 8+ | Neue Waffenmodelle mit sauberem Ironsight, Vorschaubilder für Maps/Klassen, Killcam, Last-Kill-Cam | fertig |
| 9 | Windows-Build, Tests | offen |

**Fensterglas:** Alle Fenster der Maps sind zerstörbar (Risse, Bruch, Scherben; Explosionen in der Nähe sprengen sie). Siehe docs/ARCHITECTURE.md.

## Starten

1. [Godot 4.4 oder neuer](https://godotengine.org/download) installieren (Standard-Build, kein .NET nötig).
2. Godot starten, „Importieren“ → diesen Ordner (`project.godot`) auswählen.
3. Beim ersten Öffnen importiert Godot Texturen und Sounds (ca. 10 Sekunden).
4. F5 (Projekt starten) → Hauptmenü:
   * **Training (Offline)**: Modus, Klasse, Bots wählen → **Match starten**.
   * **Online**: siehe „Online spielen“.

**Sniper** (M200): Repetierer mit Scope. Zielen öffnet ein echtes Zielfernrohr-Bild (scharf, gezoomt, mit Absehen), die Umgebung außenherum bleibt ungezoomt und unscharf;
Mausrad wechselt den Zoom, nach jedem Schuss wird repetiert (das Zielen setzt danach wieder ein). Ein Treffer von der Brust aufwärts tötet, unterer Bauch und Beine verwunden nur.
**Blendgranate** (F, 1 pro Klasse): Weißblende mit gedämpften Geräuschen und Tinnitus, abhängig von Abstand, Blickrichtung und Wänden dazwischen (ca. 5,5 s im Maximum); Bots werden ebenfalls geblendet.
Granaten und Blendgranaten, die einen Gegner direkt treffen, verursachen 5 Schaden und einen Hitmarker.

Nachladen ist animiert: Das Magazin wird gelöst, gewechselt und eingesetzt (Gewehr, MP5, Pistole), die Schrotflinte lädt Patrone
für Patrone (schnell und wuchtig, mit „Ratsch-Ratsch“-Geräusch) und lässt sich jederzeit per Schuss unterbrechen: Mit mindestens einer Patrone im
Rohr legt sie sanft an und feuert sofort. Jeweils mit passenden mechanischen Geräuschen; andere Spieler sieht man ebenfalls nachladen.

Punkte (nur pro Runde, im Scoreboard unter Tab): 1 Kill = 100, 1 Assist = 50 (Schaden von mindestens 30 in den letzten
8 Sekunden vor dem Tod des Gegners). Neue Punkte poppen wie bei Call of Duty unter dem Fadenkreuz auf.

Neu: Nach dem Tod läuft die Killcam: ein Replay der letzten 5 Sekunden aus der Sicht deines Mörders, bis zu deinem Tod
(Respawn nach 6 s, Kamera stürzt zu Boden und blendet nach ca. 0,5 s in die Killcam über, Leertaste überspringt dann sofort). Am Rundenende läuft die letzte Aktion des Siegers als Replay („Last Kill“). Beides lässt sich in den
Einstellungen unter „Killcam“ abschalten. Maps und Klassen werden im Menü, in der Lobby und bei der Kartenabstimmung
mit Vorschaubildern gewählt.

Steuerung: WASD bewegen, Maus zielen, Shift sprinten, Strg/C ducken (halten = Duckgang), Shift-Sprint + Ducken = Knie-Slide (ca. 1,5 m; Leertaste = aufstehen, zweimal = springen), Leertaste springen,
LMT schießen, RMT zielen (ADS), R nachladen, Q / 1 / 2 Waffe wechseln, G Granate und F Blendgranate (gedrückt halten = wurfbereit, loslassen = werfen), Tab Scoreboard, Esc Pause.

## Online spielen

Ein Spieler ist Host (Server und Mitspieler zugleich), die anderen treten bei.

1. Host: **Online** → Port prüfen (Standard 7777) → **Hosten**. Die Lobby zeigt die IP-Adressen des Rechners.
2. Mitspieler: **Online** → IP-Adresse des Hosts und Port eintragen → **Beitreten**.
3. Jeder wählt in der Lobby Team (nur Team Deathmatch) und Klasse. Der Host stellt Modus, Map und Bots ein und startet das Match.
4. Die Klasse kann jederzeit gewechselt werden (Lobby, Pausemenü, Endbildschirm) und gilt ab dem nächsten Respawn.
5. Nach dem Match stimmen alle 20 Sekunden (10 s Scoreboard, 10 s finale Abstimmung mit Klassenwahl) über die nächste Karte ab (Harbor, Frontier, Suburb, Mesa). Bei Gleichstand oder ohne Stimmen entscheidet der Zufall. Der Host kann stattdessen **Zur Lobby** wählen. Offline wählst du die nächste Karte direkt im Endbildschirm.

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
Bewegung, Serverkorrektur, Treffer, Kill/Respawn, Granaten, Map-Voting, Host-Abschied, Client-Abbruch mitten im Match und ein Drei-Spieler-Match; ca. 2 min):

```bash
py -3 tools/run_net_test.py "C:\Pfad\zu\godot.exe"
```

Der Import-Schritt ist nur nötig, wenn das Projekt noch nie im Editor geöffnet wurde oder neue
Skripte mit `class_name` hinzukamen (der Editor erledigt das sonst automatisch). Der Test dauert
etwa 30 Sekunden und endet mit `OK: … keine Fehler.`

## Screenshots und Vorschaubilder (Entwicklung)

Für Menü-, Waffen- und Kamera-Ansichten ohne Spielstart gibt es ein Render-Werkzeug (braucht `xvfb` und einen
OpenGL-Treiber, z. B. unter Linux; der Windows-Editor rendert ohnehin direkt):

```bash
tools/shots/run.sh <godot> fp_assault_ads /tmp/ak_ads.png      # Ego-Ansicht, Hüfte/Zielen (hip|ads), Zweitwaffe mit _sec
tools/shots/run.sh <godot> menu_settings /tmp/menu.png         # Menüs, game_pause, game_end, game_killcam, game_lastkill
tools/shots/generate_previews.sh <godot>                        # Vorschaubilder neu rendern (assets/ui/previews)
python3 tools/generate_weapon_models.py                         # Waffenmodelle + ADS-Offsets neu erzeugen
```

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

Texturen sind PBR-Sets (Albedo, `_n` Normal, `_r` Roughness; numpy + Pillow nötig). Nach dem Neuerzeugen
`godot --headless --path . --import --quit` ausführen. Stimmung je Map (Himmel, Nebel, Sonne, Farbkorrektur)
schreibt `py -3 tools/tune_atmosphere.py` in die Map-Szenen.

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

## Zuschauer-Modus

Im Menü „Training (Offline)“ startet **Zuschauer (freie Kamera)** ein Bot-Match (volle Besetzung), in dem du unsichtbar und unverwundbar frei fliegst: WASD, Leertaste hoch, Strg runter, Shift schnell, Mausrad ändert das Tempo, **F1** blendet das HUD aus/ein.

## Trainingsarena

Hauptmenü → **Trainingsarena**: Schießstand (46 × 150 m) mit fünf Bahnen und Zielen auf 10/25/50/75/100 m, Zonen-Dummys (stehend, hockend, hinter Deckung), einem Kampfhof (Deckung, Plattform, Haus mit Fensterglas). Die Dummys sind echte Spieler ohne Verhalten: Jeder Treffer zeigt **Zone, Schaden und Distanz** (unter dem Fadenkreuz und als schwebende Zahl am Ziel); sie sterben mit dem vollen Gore (Gliedmaßen, Kopf) und stehen kurz danach wieder auf. Munition und Granaten füllen sich automatisch auf, es gibt kein Kill- oder Zeitlimit.

Die Trainingsarena hat im Westen einen **Showroom**: jede Waffe (AK-47, MP5, Schrotflinte, Scharfschützengewehr, Pistole) in jeder Pose (stehend, stehend anvisiert, Hocke, Hocke anvisiert, Rennen, Hocke gehend), beschriftet. In der Trainingsarena kannst du nicht sterben.
