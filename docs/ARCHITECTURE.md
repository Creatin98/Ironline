# Architektur und technische Entscheidungen

## Grundprinzipien

* **Menschen und Bots teilen denselben Code.** `Player` (CharacterBody3D) liest jeden Physik-Tick
  einen `PlayerInputState`. `HumanController` füllt ihn aus Tastatur/Maus, `BotController` aus der KI.
  Bewegung, Waffen, Granaten, Schaden und Tod kennen keinen Unterschied.
* **Serverautoritativ.** Schaden, Kills, Punkte, Respawns und Matchzustand entscheiden nur auf der Autorität
  (`MatchManager.is_authority()`: offline immer, online der Host). Clients simulieren nur ihren eigenen Spieler
  (Prediction) und stellen alles andere aus Server-Nachrichten dar.
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
| `NetworkManager` | scripts/systems/network_manager.gd | ENet-Host/-Client, Lobby, alle RPCs, Snapshots |
| `MatchManager` | scripts/systems/match_manager.gd | Roster, Punkte, Timer, Modusregeln, Matchzustand (Server schreibt, Clients übernehmen per `apply_*`) |
| `GameDirector` | scripts/systems/game_director.gd | Szenenwechsel, Map-/Klassenregistry, Bot-Namen |

## Netzwerk (Phase 6)

**Topologie.** Host = Server und Mitspieler (Listen-Server), ENet/UDP, bis 12 Peers. Der Host simuliert alle Menschen
(aus empfangenem Input), alle Bots und die Granaten. Protokollversion `PROTOCOL_VERSION` wird beim Beitritt geprüft.

**Ablauf.** `host()`/`join()` → Client sendet `_rpc_register` (Name, Team, Klasse) → Host verteilt den Lobbyzustand
(`_rpc_lobby_state`, Peers + `MatchConfig`) → Host startet: `_rpc_begin_match` → alle laden `game.tscn` und melden
`_rpc_client_loaded` → Host baut Roster, sendet `_rpc_full_state`, startet Warmup und sendet pro Spawn `_rpc_spawn`.
Wer nicht in 12 s lädt, wird nicht abgewartet und beim späten Laden nachgezogen. Während eines Matches werden keine
neuen Verbindungen angenommen.

| Richtung | Nachricht | Kanal | Inhalt |
|---|---|---|---|
| Client → Server | `_rpc_input` | 1, unreliable ordered | Sequenz, Bewegung, Yaw, Pitch, gehaltene Tasten (60 Hz) |
| Client → Server | `_rpc_input_action` | 0, reliable | Einmal-Aktionen (Schuss, Sprung, Nachladen, Granate, Waffenwechsel) |
| Server → Clients | `_rpc_snapshot` | 1, unreliable ordered | Position, Yaw, Pitch, Geschwindigkeit, Flags, Waffe, letzte verarbeitete Input-Sequenz (20 Hz) |
| Server → Besitzer | `_rpc_owner_state` | 1 | Lebenspunkte, Munition, Granaten (10 Hz) |
| Server → Clients | Kill, Matchende, Spawn, Zustand, Schuss, Treffer-/Schadensfeedback, Granaten | 0, reliable | Ereignisse |

**Clientseitige Vorhersage.** Der lokale Spieler läuft wie offline (kein Eingabe-Lag). Pro Tick wird die Position unter der
Input-Sequenz gemerkt; der Snapshot nennt die zuletzt verarbeitete Sequenz. Abweichung > 0.25 m: weiche Korrektur (25 %),
> 3 m: hartes Setzen (Teleport, Respawn). Fremde Spieler und Bots werden zur Snapshot-Position interpoliert (mit
Extrapolation um höchstens 0.12 s). Schüsse sagt der Client vorher (Mündungsfeuer, Ton, Rückstoß, Einschläge), Schaden
entsteht nur auf dem Server: dieser führt den Hitscan mit dem übertragenen Blickwinkel des Schützen aus und schickt
Treffermarker und Schadensanzeige zurück. Die übrigen Clients erhalten Schuss und Einschläge per `_rpc_shot`.

**Klassenwechsel.** Jederzeit (Lobby, Pausemenü, Endbildschirm) über `NetworkManager.request_class_change`. Der Host
speichert die Wahl im Teilnehmer, beim nächsten Spawn tauscht `Game._sync_class` die Waffen (`Player.apply_class`), und
`_rpc_spawn` überträgt die Klasse an alle Clients. Ein lebender Spieler behält seine Waffen bis zum Respawn.

**Map-Voting.** Nach `match_ended` öffnet der Host `host_open_vote(ROTATION_MAPS)` (15 s). Clients stimmen per
`_rpc_cast_vote` ab, der Host verteilt die Zwischenstände (`_rpc_vote_tally`) und wertet aus, sobald alle Spieler gewählt
haben oder die Zeit abläuft (Gleichstand zufällig). Danach startet `host_start_match` mit der gewählten Map. Verlässt ein
Spieler die Abstimmung, zählt sie ohne ihn. Offline wählt `MatchEndScreen` die Map direkt (`map_chosen`).

**Granaten.** Nur der Server erzeugt die echte Granate (Zünder, Schaden). Clients bekommen eine Sichtkopie
(`visual_only`), die fliegt und abprallt und auf Server-Befehl explodiert (Rückfall nach 1.5 s zusätzlich).

**Bekannte Grenzen.** Keine Lag-Kompensation (Treffer zählen gegen die Serverpositionen zum Zeitpunkt des Schusses; bei
üblichen Pings von unter 80 ms fühlt es sich arcadig-direkt an). Der Rückstoß wird auf Server und Client getrennt
gewürfelt, daher können einzelne Streuschüsse abweichen. Kein Host-Wechsel: verlässt der Host, endet das Match für alle.
Kein NAT-Durchbruch; Internetspiel braucht Port-Weiterleitung.

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
| AK-47 | 35 → 25 | 22–48 m | 650 | 30/90 | spürbarer Rückstoß, Kopfschuss ×1.85 |
| MP5 | 26 → 18 | 14–32 m | 850 | 30/120 | schnell, wenig Rückstoß, +5 % Tempo, Kopfschuss ×1.7 |
| Shotgun | 8 × 25 → 4.5 | 7–18 m | 75 | 6/24 | Pumpen 0.7 s, Einzelladen |
| Pistole | 34 → 20 | 12–30 m | 420 | 12/48 | halbautomatisch, Kopfschuss ×2.0 |

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

## Polish (Phase 8)

* HUD: rote Bögen um das Fadenkreuz zeigen die Richtung des letzten Treffers (1.2 s, relativ zur Blickrichtung).
* Fremde Spieler und Bots: Mündungsfeuer am Waffenmodell in der Hand, Waffe folgt der Blickneigung, Laufwippen und
  Vorwärtsneigung beim Sprinten (`Player._animate_body`, rein visuell, nur lebende Körper).
* Performance: höchstens 64 gleichzeitige Einschlag-Effekte (`BulletImpact.MAX_LIVE`), die ältesten verschwinden zuerst.

## Waffenmodelle und Ironsight (Phase 8+)

`tools/generate_weapon_models.py` erzeugt die vier Modelle aus einfachen Meshes (je 35–55 Teile) samt Händen und Unterarmen
und schreibt die passenden `hip_position`, `ads_position` und `ads_fov` in die `.tres`-Dateien. Jede Waffe definiert eine
**Visierlinie** (`SIGHT_Y` = Höhe des Zielpunkts über dem Modellursprung, `REAR_Z` = Position der Kimme). Der ADS-Offset ist
so berechnet, dass Kimme und Korn exakt mittig liegen und die Kimme `ADS_DIST` (0.24–0.42 m) vor dem Auge sitzt: kleine
U-Kimme mit Korn und Schutzohren (AK), Diopter-Ring mit Korn im Ring (MP5), Lauf-Rippe mit Perlkorn (Shotgun),
Dreipunkt-Visier (Pistole). Wichtig für Änderungen: Teile, die zwischen Auge und Visier liegen, müssen unter der
Visierlinie bleiben, sonst verdecken sie das Bild.

## Nachlade-Animationen (Phase 8+)

* `ReloadRig` (scripts/weapons/reload_rig.gd) bewegt die Teile eines Waffenmodells per Keyframes: **Magazin** (`Mag`, Pivot an
  der Schachtoberseite), **Hände** (`LeftHand`/`RightHand`; die Unterarme bleiben am Ellbogen verankert und werden zur Hand
  gestreckt), Ladegriff (`ChargingHandle`/`CockingHandle`), Pistolenschlitten (`Slide`) und die **Schrotpatrone** (`ShellProp`).
  `apply(t)` liefert die Geräusche, deren Zeitpunkt in diesem Takt überschritten wurde, und die Kipp-Pose der ganzen Waffe.
* Stile (`WeaponData.reload_style`): `rifle` (AK: Magazin lösen, herausziehen, neues vom Gürtel, einsetzen, abklopfen,
  Ladegriff), `smg` (wie rifle, Spannhebel vorn links), `pistol` (Magazin fällt aus dem Griff, neues, Schlitten loslassen),
  `shotgun` (pro Patrone ein Zyklus: Hand zum Gürtel, Patrone zum Ladefenster, einschieben; die Waffe kippt einmal ein).
* Ablauf: `Weapon._update_reload` ruft `rig.apply`, spielt die Sounds (`reload_release`, `reload_mag_out`, `reload_mag_in`,
  `reload_slap`, `reload_bolt`, `reload_pistol_out/in`, `reload_slide`, `shell_insert`) und setzt `anim_offset/rotation` für
  den Viewmodel-Halter. Andere Spieler: `WeaponManager.begin_tp_reload` animiert deren Modell (Server-Simulation still, weil
  die `Weapon` die Sounds schon spielt; Clients über das Waffenereignis „reload“ mit 3D-Sound).
* Sounds (`tools/generate_audio.py reload`): trocken und mechanisch aus gefiltertem Rauschen und gedämpften Metallresonanzen
  (Klick, dumpfes Einrasten, Reiben des Magazins, Ladegriff mit Rückschlag), keine Töne.

## Bewegung, Kamera und HUD-Layout (Phase 8+)

* **Bordsteine/Stufen:** `Player._try_step_up` hebt den Körper bis `STEP_HEIGHT` = 0.4 m auf niedrige Hindernisse
  (Test mit `test_move`: frei darüber, kein Hindernis auf der Stufe, Boden dahinter), ohne Sprung. Die Kamera zieht über
  `_step_view_offset` weich nach (kein Ruck), auch beim Hinuntergehen. Höhere Wände blockieren wie zuvor.
* **Laufwippen:** Kamera-Bob (hoch/runter, links/rechts, leichtes Rollen) und die Waffe schwingt beim Gehen/Sprinten mit
  (`WeaponManager`, schwächer im ADS). **Rückstoß:** der Viewmodel-Kick wird im ADS auf 15 % gedämpft und begrenzt, der
  Kamera-Rückstoß ist auf 6° gedeckelt, das Visier bleibt im Bild.
* **HUD:** `HUD._layout` setzt jeden Block (Punkte, Zeit, Killfeed, Gesundheit, Munition) in seine Ecke mit symmetrischem
  Rand (`GameSettings.hud_margin`) und Skalierung; `hud_offsets` speichert die im **HUD-Editor** (Einstellungen →
  „HUD anpassen …“ (im Spiel), Elemente ziehen, Esc/Fertig) gesetzten Verschiebungen. Gesundheit zeigt Prozent (100 % = voll).

## Punkte und Assists (Phase 8+)

* **1 Kill = 100 Punkte** (auch Kopfschuss, kein Bonus), **1 Assist = 50 Punkte** (`GameModeBase.POINTS_KILL/POINTS_ASSIST`).
  Teamkill −50, Selbstmord −25 (wie bisher). Die Punkte zählen nur innerhalb der laufenden Runde und erscheinen im
  Scoreboard mit Kills, Tode, Assists, Punkte; sie werden nicht gespeichert.
* **Assist:** `Health` merkt sich Schaden pro Angreifer (8 s Fenster). Wer ≥ 30 Schaden gemacht hat, das Opfer nicht selbst
  tötet und ein Gegner des Opfers ist, bekommt den Assist (`Health.get_assisters` → `MatchManager.report_kill`).
* Online rechnet nur der Server. `_rpc_kill_event` überträgt die Punktestände (`stats_dict`, jetzt mit Assists) und die
  Assist-Empfänger, damit deren HUD das Popup zeigt. `PROTOCOL_VERSION` = 4.
* **Popups** (`HUD._on_scored`): stapeln sich unter dem Fadenkreuz (max. 4), poppen groß auf, schweben und blenden aus:
  „+100 KILL“ (Gold, mit „3 IN FOLGE“), „+100 KOPFSCHUSS“ (Rot, größer), „+50 ASSIST“ (Blau, mit leisem Ton).

## Treffer- und Kill-Feedback (Phase 8+)

* **Hitmarker** (`HUD._draw_hitmarker`): weißes X bei Treffer, **rotes Doppelkreuz (X + Plus)** bei Kopfschuss, großes rotes X mit
  Burst-Ring bei Kill, rotes Doppelkreuz mit Ring bei Kopfschuss-Kill. Pop-Animation (startet groß, setzt sich), Kill 0.5 s.
* **Sounds** (`tools/generate_audio.py hits`): Treffer = trockener Tick + Thud, Kopfschuss = scharfer Knall + metallisches
  Ping, Kill = Thunk + zwei aufsteigende Glockentöne, Kopfschuss-Kill = höher mit Schimmer. Die Kill-Töne werden mit jedem
  Kill in Folge höher (bis +8 Stufen). Granaten-Kills bekommen den Kill-Ton über `participant_killed`.
* **Gefühl:** Kamera-FOV-Punch (`PlayerCamera.kick_fov`), kurzes weißes Aufblitzen, Score-Popup mit Pop und Serie
  („3 in Folge“), Kopfschuss-Popup in Rot.
* Kopfschuss-Multiplikatoren: AK ×1.85, MP5 ×1.7, Pistole ×2.0 (Shotgun ×1.0: Streuschüsse haben keinen Kopfschuss-Bonus).

## Killcam und Last-Kill-Cam (Phase 8+)

* **Killcam:** Beim eigenen Tod spielt `Game._start_killcam` ein **Replay der letzten 5 Sekunden** aus der Sicht des
  Schützen ab, bis zu unserem Tod (+0.9 s). Die echten Spieler spielen unsichtbar weiter, der `ReplayRecorder` (30 Hz,
  12 s Fenster, auf jeder Maschine aus dem Gesehenen) posiert stattdessen **Geister-Kopien** (`player.tscn` ohne Kollision,
  nicht in der Gruppe `players`). Mündungsfeuer und Schussgeräusch kommen aus dem Schuss-Flag der Aufzeichnung. Danach
  normale Todesansicht bis zum Respawn. Menschen respawnen nach `HUMAN_RESPAWN_DELAY` = 6 s (Killcam), Leertaste
  überspringt ab 0.5 s (Sturz der Kamera `Player._play_fall_camera` → Fade → Killcam, `Game._death_sequence`) (`NetworkManager.request_skip_respawn` → Server `Game.skip_respawn`), Bots nach der Moduszeit (1.5 s).
* **Anzeige:** Beide Kameras haben einen **Vignette-Shader** (dunkle Ränder) und unten einen Infoblock: Name des
  Schützen in Teamfarbe, Waffe (+ „KOPFSCHUSS“), **Assist: Namen** (aus `MatchManager.kill_assists`, wird mit dem Kill am
  Eintrag des Recorders gespeichert), dazu Respawn-Zähler und Skip-Hinweis.
* **Last Kill – Zeitlupe:** Normale Geschwindigkeit, ab dem ersten Schuss der tödlichen Salve (spätestens 0.35 s vor dem Kill)
  läuft der Replay mit `Engine.time_scale` 0.3 und dumpferem Ton bis zum Ende (`ReplayRecorder.SLOWMO_SCALE`). Die
  Zeitskala wird bei Ende, Abbruch und Verlassen der Szene zurückgesetzt.
* **Last Kill – Abspann:** Danach löst sich die Kamera aus der Szene (die eingefrorenen Spieler bleiben stehen), fährt über die
  Map (`Game._start_outro`, 3.2 s) und umkreist sie langsam; das Scoreboard blendet nach 1.6 s ein. Leertaste überspringt.
* **Last Kill:** `ReplayRecorder` zeichnet auf jeder Maschine mit 30 Hz die sichtbaren Posen aller Spieler der letzten 12 s
  auf (Position, Blick, Ducken, lebt, Waffe, Schuss). Am Rundenende sucht er den letzten Kill des Siegers (Team/Spieler),
  friert die Welt ein und spielt 3 s davor bis 1.6 s danach die echten Spieler-Nodes ab, Kamera in den Augen des Schützen.
  Kein Netzwerkverkehr nötig. Liegt der Kill außerhalb des Fensters (z. B. Zeitlimit), entfällt der Replay.
* Beides hängt an `GameSettings.killcams`.

## Menü-Oberfläche und Vorschaubilder

`PreviewPicker` (Karten mit Bild, Titel, Badge) wird für Map und Klasse in Training, Lobby, Pausemenü, Endbildschirm und
Kartenabstimmung genutzt. Bilder liegen in `assets/ui/previews/` (gerendert mit `tools/shots/generate_previews.sh`,
`GameDirector.get_map_preview/get_class_preview`). Fenster werden mit `CenterContainer` zentriert; absolute
`position`-Werte auf Ankern verrutschen, wenn der Elternknoten noch keine Größe hat.

## Spawnsystem

`SpawnSystem.pick_spawn`: Kandidaten (Teampunkte + neutrale), Score = min. Gegnerdistanz (max 40) +
Zufall − Strafen (Gegner < 9 m, besetzt, kürzlich benutzt, Sichtlinie von Gegnern).

## Assets

Texturen (512², tileable Value-Noise), Sounds (synthetisierte WAVs) und Materialien werden von den
Python-Skripten in `tools/` erzeugt – keine Fremdinhalte, alles reproduzierbar.

## Physik-Layer

1 World, 2 Players, 3 Projectiles, 4 Hitboxes (reserviert).

* **Slide:** `Player._start_slide` (Ducken-Flanke während Sprint, Tempo ≥ 6.6, Abklingzeit 0.9 s). Gleitet `SLIDE_TIME` 0.5 s mit
  abnehmendem Tempo (v0·(1−t/T)^1.4, leichte Lenkung), danach geduckt (Taste gehalten) oder stehend. Leertaste im Slide/Duck
  steht auf (`_crouch_suppressed`), erst die zweite springt. Netzwerk: `SNAP_SLIDE` (Protokoll 5). Kamera/Waffe senken sich
  über `PlayerCamera.sliding` bzw. `_slide_blend`; Sound `slide.wav`.

* **Menümusik:** `AudioManager.play_music()/stop_music()`; spielt alle mp3/ogg/wav aus `assets/audio/music/` nacheinander (Bus „Music“,
  Fade ein/aus). `MainMenu._ready` startet sie, `Game._ready` stoppt sie. Ohne Dateien passiert nichts.

* **Blut:** `BloodFx.burst` (Partikel + Splats auf Wand/Boden per Raycast, max. 90, 40 s) wird von `Weapon._spawn_impact` bei Spielertreffern
  auf allen Maschinen erzeugt; `HUD._add_blood_splats` zeichnet einzelne Bildschirm-Spritzer (`BloodFx.splat_texture`, prozedural).
  Waffenzucken beim Getroffenwerden: `WeaponManager._on_owner_damaged` (auch im ADS).
* **Minimap:** `Minimap` (HUD-Block „Minimap“, verschiebbar im HUD-Editor): SubViewport mit Orthokamera von oben, dreht mit der Blickrichtung,
  zeigt 60 m Breite; Overlay: eigener Pfeil, Teammates, gegnerische Schüsse (`GameEvents.shot_fired`, 1.4 s Blitz).
* **Abbrechen:** Sprint bricht Nachladen/Granate ab (`WeaponManager.cancel_for_sprint`), Waffenwechsel bricht Granate ab und
  darf das Hochnehmen unterbrechen (schnelles Wechseln); `LOWER_TIME` 0.11 s, `draw_time` ~35 % kürzer.

* **Ladebildschirm:** `LoadingScreen` (CanvasLayer 100 unter dem Root, überlebt den Szenenwechsel) wird von `GameDirector.start_match` gestartet:
  Kartenbild, Zufalls-Tipp, Ladebalken, 7 s; Menümusik läuft weiter und blendet die letzten 2.2 s aus. `Game._ready` wartet auf
  `GameDirector.loading_finished`, erst danach Roster/„alle Spieler geladen“/Countdown. Tests/Shots setzen `_skip_loading_screen`.
* **Countdown:** `MatchManager.WARMUP_TIME` = 8 s (`warmup_time` für Tests). Schwarz-Weiß-Shader `Game._update_gray`: Farbe kehrt linear
  zurück, 0.5 s vor Ablauf voll farbig.
* **Killcam:** Aufnahme enthält `is_aiming`; `ReplayRecorder.killer_aim` schiebt die Waffe in die Visierlinie (`Player.replay_aim`), FOV und
  Fadenkreuz (`Game._draw_cam_cross`) folgen. Bildschirm-Blut (`HUD`, eigene CanvasLayer) bleibt im Tod/Killcam stehen und verblasst erst nach dem Respawn.

* **Minimap (neu):** keine Kamera mehr; `Minimap.build_from` sammelt die Grundrisse der Kollisionsformen (Boden dunkel, Wände/Häuser/Kisten
  hell mit Umriss) und zeichnet sie gedreht. Mates dauerhaft als Pfeile, Gegner nur als roter Pfeil beim Schuss (1.6 s, mit Blickrichtung).
* **Hit-/Kill-Sounds:** `make_hit_feedback` – Transienten aus Rauschen + inharmonische Metall-Partiale (> 2 kHz), Kill mit Clang und Sub-Punch,
  Kopfschuss als Doppel-Snap, Kopfschuss-Kill als Kombination aus beidem (Lautheit: Treffer < Kopfschuss < Kill < Kopfschuss-Kill).

* **Einstellungen (3 Reiter: Grafik / Sound / Spiel):** `SettingsPanel` ist datengetrieben (`_entries`: Typ, `GameSettings`-Eigenschaft, Steuerelement),
  dadurch laden/übernehmen/„Reiter auf Standard“ für alle gleich. Sound-Regler wirken sofort (Vorschau-Sample beim Loslassen), „Zurück“ macht sie rückgängig,
  „Übernehmen“ speichert (`user://settings.cfg`, Abschnitt `audio_volumes`, `video`, `hud`). Grafik: Voreinstellung (Niedrig/Mittel/Hoch) füllt die Einzelwerte,
  manuelle Änderung → „Benutzerdefiniert“. `GameSettings.apply_scene` setzt Schatten/Post-Processing in der Map, `effects_scale()` skaliert Partikel,
  `view_distance_m()` die Kamera-Fernebene.
* **Audio-Architektur:** `AudioCategories.ENTRIES` ist die einzige Quelle (Bus, Eltern-Bus, Label, Standardwert, Vorschau-Sound). Busse werden beim Start
  angelegt (`ensure_buses`, idempotent): Master → Music / UI / SFX (→ Weapons, Grenades [+Limiter], Reload, Handling, Movement, Hitmarker, Headshot, Kill, HitOther)
  / Ambience (→ Birds, Wind, Water, Distant, Breath, AmbientOther). `AudioManager.play_*` wählt den Bus über den Dateinamen (`EXACT_SOUNDS`/`SOUND_PREFIXES`).
  **Neue Soundkategorie = ein Eintrag in `ENTRIES`** (Regler, Speichern, Bus entstehen automatisch); neue Sounddatei = Zeile in `EXACT_SOUNDS`/`SOUND_PREFIXES`.
* **Umgebung:** `AmbienceSystem` (pro Map-Profil): Wind-/Wasser-Loops, Vogel-/Möwenrufe, ferner Jet; eigener Atem nach langem Sprint (`Player._update_states`).
  Sounds per `tools/generate_audio.py ambience`.

* **Spawns:** `SpawnSystem.is_blocked/free_position_near` prüfen die Spieler-Kapsel gegen die Welt; blockierte Punkte werden beim Wählen stark abgewertet und
  notfalls zur nächsten freien Stelle verschoben. Der Smoke-Test prüft alle Spawnpunkte aller Maps (Punkte in Kisten/Wänden wurden korrigiert).
* **Bildschirm-Blut:** verblasst beim Tod schnell (0.5 s) und wird beim Respawn gelöscht – nichts im Todesblick/Killcam. Killcam-Vignette stärker.
  Killer-Ansicht (Killcam/Last Kill) blendet die langen Ärmel aus (`Player.set_replay_sleeves_hidden`), damit sie beim Nachladen nicht durchs Bild schwingen.

* **Waffenmodelle ohne Flackern:** `tools/generate_weapon_models.py` erkennt gleichgerichtete, deckungsgleiche Flächen verschiedener Materialien (z-fighting) und
  zieht die kleinere Box um 0.8 mm vor (`Scene.coplanar_faces` / `adjust_all`). Unterarme sind kürzer (max. 0.36 m) und dicker.
* **Last Kill Cam:** Replay 3.5 s vor / 1.4 s nach dem Abschuss; in der Zeitlupe zoomt das FOV auf das Opfer (`ReplayRecorder.last_kill_fov`), ein roter
  Kill-Marker liegt im Moment des Abschusses auf dem Opfer (`victim_marker`). Beim Zielen sitzt die Waffe des Schützen exakt wie das First-Person-Viewmodel
  (`Player.replay_aim` mit `ads_position` relativ zur Kamera). Bildschirm-Blut wird in Replays und am Matchende ausgeblendet.

* **Matchende:** Nach dem letzten Kill läuft das Spiel `MatchManager.runout_time` (1.7 s) weiter: alle gleiten über `Player.run_out` (Verzögerung 7 m/s²) langsam
  zum Stehen, das HUD blendet aus, das letzte Opfer fällt. Danach startet die Last Kill Cam (3.5 s davor, 2.4 s danach; Zeitlupe bis 0.7 s nach dem Kill,
  dann normales Tempo, damit man das Hinfallen sieht), dann Abspann und Scoreboard wie zuvor. Der rote Kill-Marker wurde entfernt.

* **Last Kill Cam (Kino-Look):** `Game._build_bars` – 21:9-Balken im HUD-Stil (halbtransparent, Akzentlinie): oben „LETZTER ABSCHUSS“, unten eine Namensbox des Schützen
  (Teamfarben-Streifen, Waffe, Kopfschuss, Opfer, Assists). Die Balken fahren ein (`_update_bars`). Die normale Killcam behält ihre Textanzeige.
* **Minimap:** Mates immer als blaue Pfeile (leuchten beim Schuss auf), eigener Pfeil leuchtet beim Schuss, Gegner nur als rote Punkte beim Schuss.
* **Namen/Totenkopf:** Gegnernamen nur mit Tiefentest (nicht durch Wände), Mates durch Wände (`Player._update_name_label`). Stirbt ein Mate, schwebt
  3 s ein dezenter Totenkopf (`DeathSkull`) über der Stelle, durch Wände sichtbar, nur für das eigene Team.
* **Blut-Ebene:** Bildschirm-Blut liegt in Canvas-Layer 1 (hinter dem HUD in Layer 2). **Slide:** endet nur nach der Slidezeit oder per Leertaste (steht auf; gehaltenes Sprint+Vorwärts bricht nicht ab). **AK-Nachladen:** der linke Unterarm schrumpft beim Übergreifen zum Spannhebel weg, die Hand führt links an der Waffe vorbei.
