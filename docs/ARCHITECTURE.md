# Architektur und technische Entscheidungen

## Grundprinzipien

* **Menschen und Bots teilen denselben Code.** `Player` (CharacterBody3D) liest jeden Physik-Tick
  einen `PlayerInputState`. `HumanController` füllt ihn aus Tastatur/Maus, `BotController` aus der KI.
  Bewegung, Waffen, Granaten, Schaden und Tod kennen keinen Unterschied.
* **Serverautoritativ vorbereitet.** Alle Schadens-, Kill- und Punkteentscheidungen laufen nur, wenn
  `MatchManager.is_authority()` wahr ist (offline immer). In Phase 6 werden die Aufrufe
  `take_damage`, `report_kill`, `respawn_at` zu RPCs; die Zustandsobjekte (`Participant`,
  `MatchConfig`, `MatchManager.to_dict()`) sind bereits serialisierbar.
* **Signal-Bus statt Querverweise.** `GameEvents` (Autoload) trägt alle Ereignisse; HUD, Audio und
  Spielfluss hängen sich dort ein. Kein UI-Skript kennt den Spieler direkt.
* **Daten als Ressourcen.** Waffen (`WeaponData`) und Klassen (`ClassData`) sind `.tres`-Dateien;
  Balancing ohne Codeänderung.

## Autoloads

| Name | Datei | Aufgabe |
|---|---|---|
| `GameSettings` | scripts/systems/game_settings.gd | Einstellungen laden/speichern/anwenden (`user://settings.cfg`) |
| `GameEvents` | scripts/systems/game_events.gd | Signal-Bus |
| `AudioManager` | scripts/systems/audio_manager.gd | Gepoolte 2D/3D-Soundplayer, Busse Master/Music/SFX/UI |
| `MatchManager` | scripts/systems/match_manager.gd | Roster, Punkte, Timer, Modusregeln, Matchzustand |
| `GameDirector` | scripts/systems/game_director.gd | Szenenwechsel, Map-/Klassenregistry, Bot-Namen |

## Szenenfluss

`main_menu.tscn` → `GameDirector.start_match(config)` → `MatchManager.prepare_match` →
`game.tscn` lädt die Map in `MapContainer`, baut den Roster, startet Warmup (3 s) →
`RUNNING`: alle Teilnehmer spawnen → Kills über `Player.died` → `Game._on_player_died` →
`MatchManager.report_kill` → Killlimit/Zeitlimit → `ENDED` → `MatchEndScreen`
(„Nächste Runde“ startet dieselbe Konfiguration neu; Map-Voting kommt in Phase 7).

## Spieler

* Kapsel 1.8 m (geduckt 1.2 m), Augenhöhe = Höhe − 0.18 m. Gehen 5.6, Sprint 7.7, Ducken 2.9 m/s.
  Gravitation 15 m/s² für ein knackiges Sprunggefühl.
* Mauslook wird **pro Event** angewendet (keine Physik-Tick-Latenz); Bots liefern `look_delta` pro Tick.
* `PlayerCamera` (Head): Pitch, Bobbing, Landungs-Dip (Feder), Recoil-Offset mit Erholung,
  Screenshake, FOV-Blend für ADS/Sprint. Alles über `GameSettings` abschaltbar.
* Kopfschuss: Treffer oberhalb von `global_position.y + Höhe − 0.36`.
* Lebenspunkte 100, Regeneration nach 4 s mit 45/s (CoD-Stil).

## Waffen

`WeaponManager` (unter der Kamera) hält zwei `Weapon`-Instanzen, wechselt (Senken 0.18 s + Ziehzeit),
wirft Granaten und bewegt den Viewmodel-Holder prozedural (Hüfte/ADS-Position, Sway, Sprint-Pose,
Kick, Reload-/Pump-Animation aus `Weapon.anim_offset/anim_rotation`).

`Weapon` = Hitscan via `PhysicsDirectSpaceState3D.intersect_ray` (Maske World|Players), Pellets für die
Shotgun, Streuung als Kegel (Hüfte/ADS/Bewegung/Luft/Ducken + Aufbau pro Schuss), Schaden mit Distanz-Falloff,
Rückstoß als Kamera-Offset + Modell-Kick. Zustände: HOLSTERED, DRAWING, IDLE, RELOADING, PUMPING.
Shotgun lädt einzelne Patronen und kann durch Schießen abgebrochen werden.

| Waffe | Schaden | Falloff | RPM | Magazin | Besonderheit |
|---|---|---|---|---|---|
| AK-47 | 35 → 25 | 22–48 m | 650 | 30/90 | spürbarer Rückstoß |
| MP5 | 26 → 18 | 14–32 m | 850 | 30/120 | schnell, wenig Rückstoß, +5 % Tempo |
| Shotgun | 8 × 22 → 4 | 7–18 m | 75 | 6/24 | Pumpen 0.7 s, Einzelladen |
| Pistole | 34 → 20 | 12–30 m | 420 | 12/48 | halbautomatisch, Kopfschuss ×1.5 |

Granate: RigidBody, Zünder 2.4 s nach Wurf, Radius 6.5 m, 135 → 15 Schaden (quadratischer Falloff),
Sichtlinienprüfung gegen Weltgeometrie.

## Maps

Maps erben von `BlockMap` und beschreiben Geometrie als Liste von Blöcken (`box`, `cylinder`, `ramp`,
`room_walls`, `header`, `window`, `fence`, `car`). `BlockMap` erzeugt StaticBody3D + CollisionShape3D +
MeshInstance3D unter einer `NavigationRegion3D`, dazu Spawnpunkte und die Kill-Zone. Materialien sind
triplanar (Welt-UVs), daher braucht keine Box UV-Mapping.

| Map | Größe | Thema | Lanes | Vertikal |
|---|---|---|---|---|
| Harbor | 30 × 64 m | Yacht: Bug (Rot), Heck (Blau), Kabinen, Salon, Maschinenraum | Backbord / Aufbau / Steuerbord | Sonnendeck über zwei Treppen |
| Frontier | 60 × 46 m | Kleinstadt: Tankstelle (Rot), Laderampe (Blau), Gassen, Läden | Gasse mit Garagen / Hauptstraße mit Kiosk / Ladenzeile | Zwei Dächer mit Außentreppen |
| Suburb | 56 × 44 m | Vorstadt: zwei zweistöckige Häuser diagonal, Sackgasse mit Bus | Hinterhöfe / Straße / Garagen | Obergeschosse mit Balkon, Außentreppen |
| Testarena | 60 × 44 m | Trainingsmap | drei Lanes | Catwalk, erhöhter Raum |

**Navigation.** Jede Map backt beim Laden ein `NavigationMesh` aus den statischen Collidern
(Zelle 0.25 m, Agent-Radius 0.5 m, max. Steigung 42°, Stufe 0.5 m). Der Nav-Server iteriert Maps
asynchron; `BlockMap.navigation_ready` wird erst gesetzt, wenn eine Probeabfrage am ersten Spawnpunkt
ein Ergebnis liefert (`wait_navigation_ready()` zum Abwarten). Maps liefern außerdem `get_lanes()`
(Wegpunkte je Lane von Nord nach Süd, plus Dach-/Hausrouten) und `get_cover_points()` für die Bot-KI.
Der Smoke-Test prüft für jede Map, dass alle Lane- und Spawnpunkte auf dem Mesh liegen und ein
Nord-Süd-Pfad über die Mitte existiert.

## Bots

`BotController` (Kind des Player-Nodes, nur auf der Autorität aktiv) schreibt wie der
`HumanController` ausschließlich in den `PlayerInputState`. Zustände:

| Zustand | Verhalten |
|---|---|
| PATROL | Lane-/Deckungspunkt wählen (in TDM bevorzugt die eigene Lane `id % 3`, Richtung Gegner-Schwerpunkt, mind. 8 m entfernt), Pfad über `NavigationServer3D.map_get_path`, sprinten wenn weit |
| COMBAT | Gegner sichtbar: außerhalb der Waffenreichweite nähern, sonst strafen; Feuer in Bursts (`bot_burst_shots`) mit Reaktionszeit und Zielfehler; ADS ab 9 m; Granate bei 9–26 m |
| SEARCH | Letzte bekannte Position (Sicht, Schussgeräusch, Explosion) aufsuchen, nach 6 s zurück |
| RETREAT | Unter `retreat_health` zum weitesten Deckungspunkt, ducken, bis Regeneration > 85 % |

Wahrnehmung alle 0.12 s: Distanz < Sichtweite, Blickwinkel, Sichtlinie (Welt-Layer) auf Brust oder Kopf.
Munition: leer im Kampf → Waffenwechsel, sonst nachladen; außerhalb des Kampfs unter 45 % nachladen.
Stuck-Erkennung springt nach 1.3 s und wählt nach 3 s ein neues Ziel. Drei Profile in `BotDifficulty`
(Reaktion 0.85/0.45/0.25 s, Zielfehler 7.5/3.8/2.2°, Sichtweite 32/45/50 m, Granatenchance, Rückzug).

## Spawnsystem

`SpawnSystem.pick_spawn`: Kandidaten (Teampunkte + neutrale), Score = min. Gegnerdistanz (max 40) +
Zufall − Strafen (Gegner < 9 m, besetzt, kürzlich benutzt, Sichtlinie von Gegnern).

## Assets

Texturen (512², tileable Value-Noise), Sounds (synthetisierte WAVs) und Materialien werden von den
Python-Skripten in `tools/` erzeugt – keine Fremdinhalte, alles reproduzierbar.

## Physik-Layer

1 World, 2 Players, 3 Projectiles, 4 Hitboxes (reserviert).
