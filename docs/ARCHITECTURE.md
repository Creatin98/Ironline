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

**Map-Voting.** Nach `match_ended` öffnet der Host `host_open_vote(ROTATION_MAPS)` (20 s). Clients stimmen per
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
| Mesa | 64 × 56 m | Villenanwesen am Wüstenhang (an z = 0 gespiegelt): Spawn-Plätze Nord/Süd | Garten mit Sonnenterrasse (+1.8) / Haupthaus + versenkter Innenhof (−1.2) / Garagentrakt mit Gasse | Loft + Balkon (+3.5), Katwalk, Dachterrasse, Innen- und Außentreppen |
| Testarena | 60 × 44 m | Trainingsmap | drei Lanes | Catwalk, erhöhter Raum |

**Mesa** (`mesa.gd`, Grundriss im Kopfkommentar): Alle Bauteile sind einmal für die „lokale“ Hälfte (z' = Abstand zur
Mittellinie) geschrieben und per Spiegelhelfer (`_bx`, `_room`, `_rp`, `sgn`) für beide Teams platziert; fair, aber Garten und
Garagenflügel haben je einen eigenen Charakter. Mitte: Haupthaus (2 Geschosse, Salon, Innentreppe, Balkon über dem Innenhof)
und versenkter Innenhof mit vier Rampen. Querverbindungen: Seitentüren, Hof-Rampen, Garagenkorridor (z −2..2), Service-Gasse
(x 27..31), Außentreppen zu Loft und Garagen-Dach. Spawns liegen hinter Mauern und Sichtblenden (Hintertüren ohne Blick in den
Spawn). Vegetation (`vegetation.gd`): Palmen, Büsche und Hügel als MultiMesh; `foliage.gdshader` bewegt Wedel und Büsche im Wind.
Mesa-Dekor (`mesa_scenery.gd`, rein visuell ohne Kollision, Layout/Navigation unberührt): roter Spiralturm im Innenhof, Holzfassaden und auskragende Dächer, LED-Linien, Team-Banner und Wimpelketten (`cloth.gdshader`, Wind im Vertex-Shader), Staub-Partikel (CPUParticles3D), Wolkenebene (`clouds.gdshader`), Blumenbeete, Felsen, Kletterpflanzen, Pooldeck, Innenräume und Leben auf den Hügeln (Büsche/Palmen anhand der Hügelhöhe, ferne Villen). God Rays kommen aus dem volumetrischen Nebel (Forward+, Dichte/Anisotropie in `tools/tune_atmosphere.py`).

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

Texturen (512², tileable, Albedo + Normal + Roughness), Sounds (synthetisierte WAVs) und Materialien werden von den
Python-Skripten in `tools/` erzeugt – keine Fremdinhalte, alles reproduzierbar.

## Fensterglas (zerstörbar)
- **Erkennung**: `MapDetail` findet Fensteröffnungen (Sturz + Brüstung, auch im Obergeschoss) und liefert pro Fenster Mitte, Größe,
  Achse. `BlockMap` baut daraus ein `GlassField` mit je einem `GlassWindow` (id = Reihenfolge, auf allen Maschinen gleich).
  Türen bleiben offen. Harbor hat dafür 4 Brückenfenster, die Testarena 4 Fenster bekommen.
- **Glas**: dünne Box mit `window_glass.gdshader` (klar, Fresnel-Reflexion, Schleier/Schmutz, Glanzband). Einschläge (bis 8) zeichnet
  der Shader prozedural als Verbundglas: Krater, Radialrisse mit Gabelungen, Ringrisse, Frostfleck; mehr Schaden = größere Risse.
  Jede Scheibe hat 55–90 Lebenspunkte (Variation); Gewehr ≈ 3 Treffer, Schrot/Scharfschütze deutlich weniger.
- **Kollision**: intaktes Glas liegt auf Physik-Layer 32 (hält Spieler auf, Kugeln und Bot-Sicht ignorieren es: ein Schuss geht durch und
  beschädigt jede Scheibe auf seinem Weg). Zerbrochen: Körper entfernt, nur kleine Randsplitter (rein visuell) bleiben im Rahmen.
- **Bruch**: `GlassShards` = 16–38 Dreiecke in EINEM MultiMesh, per Skript bewegt (kein Physik-Körper), fallen auf den Boden unter dem
  Fenster, einmal abprallen, nach 8 s verschwinden; max. 8 Gruppen gleichzeitig. Dazu Funkenpartikel und Sounds (`glass_*`).
- **Granaten**: Eine geworfene Granate zerschlägt intaktes Glas auf ihrem Weg komplett (`GlassField.on_grenade_move`, Host) und fliegt
  ungebremst durch die Öffnung; sie kann also nie durch heile Scheiben fliegen.
- **Explosionen**: `GlassField.on_explosion` (Host, aus `Grenade.explode`): Reichweite 1,1 × Radius, Wirkung fällt mit der Entfernung
  ab, Wände dazwischen schwächen sie auf 30 %; nahe Scheiben brechen, weitere reißen nur an.
- **Killcam**: Jede Scheibe führt eine Verlaufsliste (Zeit, Position, Richtung je Einschlag, Bruchzeit; gleiche Uhr wie der
  `ReplayRecorder`). `ReplayRecorder` ruft `GlassField.replay_begin/step/end`: Die Anzeige geht auf den Zustand zu Replay-Beginn zurück,
  Risse, Bruch, Scherben und Sounds erscheinen genau zu ihrer Zeit; Logik und Kollision laufen währenddessen live weiter und nach dem
  Replay zeigt die Scheibe wieder den echten Zustand. Gilt für Killcam und Last-Kill-Cam.
- **Multiplayer**: Der Host entscheidet (`MatchManager.is_authority()`), Clients zeigen nur. Events: `_rpc_glass` (Treffer/Bruch),
  `_rpc_glass_blast` (alle von einer Druckwelle betroffenen Scheiben in einem Paket), `_rpc_glass_state` für späte Lader.
  Splitter werden nie übertragen, jede Maschine simuliert sie lokal. `PROTOCOL_VERSION` = 10.

## Waffen am Boden
- Stirbt ein Spieler (oder Bot), legt der Host dessen Hauptwaffe mit Restmunition als `WeaponPickup` ab (`Game._drop_primary_weapon`),
  bis zu 10 gleichzeitig, 45 s Lebensdauer. Der Pickup fällt aus Handhöhe taumelnd zu Boden, liegt flach auf der Seite, hat dezenten weißen Leuchtrand (`material_overlay`) und Label (`[E] aufnehmen` in 2 m).
- Überlaufen einer Waffe desselben Typs (< 1 m, Reserve ≤ Standardreserve) gibt ein Magazin (`Game._check_ammo_pickups`, nur Host; `apply_pickup_take` mit `mag = AMMO_ONLY`), HUD-Aufleuchten + Sound.
- **E** (`interact`, Bit `ACT_USE`) tauscht die nächste Waffe in Reichweite gegen die eigene Hauptwaffe (`Game.try_pickup`, nur Host);
  die eigene bleibt mit ihrer Munition liegen. Sekundärwaffe, Granaten und Blendgranaten bleiben unverändert (`Player.swap_primary`).
- Sync: `_rpc_pickup_spawn`, `_rpc_pickup_take`, späte Lader bekommen alle liegenden Waffen nachgereicht. `PROTOCOL_VERSION` = 11.

## Optik (Visual Overhaul)
- **Materialien**: `assets/materials/*.tres` nutzen Albedo-, Normal- und Roughness-Map (triplanar, Welt-UV).
  Waffen (`weapon_metal/polymer/wood`) und Stoff (`cloth`) nutzen Objekt-Triplanar. Normal-Maps sind als Normal-Map importiert.
- **MapDetail** (`scripts/maps/map_detail.gd`): rein visuelle Architektur ohne Collider/Navigation. `BlockMap` führt die
  Visuals aller Blöcke pro Material zu einem Mesh zusammen (ein Draw Call je Material statt je Block) und ergänzt automatisch
  Sockel, Dachkranz, Pilaster, Fallrohre, Klimageräte, Fenster-/Türrahmen (erkannt an Sturz + Brüstung). Je Map ergänzt
  `build_detail(d)` Props (Laternen, Fässer, Paletten, Masten/Kabel, Markierungen, Lampen mit Fülllicht).
- **Atmosphäre**: `tools/tune_atmosphere.py` schreibt Himmel, Ambient, Nebel (+ volumetrisch, nur Forward+), SSAO, Glow,
  Farbkorrektur und Sonne je Map (Harbor kühl/dunstig, Frontier warm/staubig/kontrastreich, Suburb gedämpft/spätnachmittag).
- **Soldat** (`humanoid_rig.gd`): Teile werden pro Pivot und Material zu einem Mesh vereint (`_part`/`_commit_parts`); Outline
  per Normalen-Offset-Shader auf geglätteten Kopien. Ragdoll und Animation unverändert (Pivots bleiben).
- Rot-Overlay (`DamageFx`), HUD, Gameplay, Waffenverhalten und Audio sind unverändert.

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

* **Figuren:** `HumanoidRig` (scripts/player/humanoid_rig.gd) ersetzt Kapsel+Kopf: Beine (Lauf-/Sprintzyklus, Hocke, Slide, Sprungpose), Arme per Zwei-Knochen-IK
  zu den Händen des Waffenmodells (folgt Zielen/Nachladen), Kopf folgt dem Blick. Hauttöne beige hell–dunkel, Haare/Kleidung neutral nach Teilnehmer-ID.
  Umriss: größere Kopie jedes Teils mit Shader (cull_front, unshaded, HDR-Energie), rot = Gegner, blau = Mates (aus Sicht des Spielers, auch Namen), mit Tiefentest
  → nie durch Wände. Der Hitbox (Kapsel) blieb unverändert.
* **Granatenwurf:** `GrenadeView` (Ego-Arm mit Granate, linke Hand zieht den Splint, Ausholen, Wurf; Dauer 1.0 s, Abwurf bei 62 %), Sounds `grenade_draw`/`grenade_pin`/
  `grenade_lever` zu festen Zeitmarken (`WeaponManager.GRENADE_SOUNDS`, auch 3D für andere Spieler).
* **Schrotflinte:** `WeaponData.impact_feel` (2.2): stärkerer Rückstoß, Kamerawackeln, FOV-Stoß, größeres Mündungsfeuer, wuchtigeres Pumpen und Nachladen
  (Kick pro Patrone). Fadenkreuz = kleiner Ring (Radius 11 + Streuung·3.6).

* **Umgebungsgeräusche standardmäßig stumm:** Alle Einzelregler der Gruppe „Umgebung“ (Vögel, Wind, Wasser, Flugzeuge, Atmen, Sonstiges) stehen im Standard auf 0 %,
  „Umgebung allgemein“ auf 100 %. Die Sounds und Regler bleiben erhalten. `AmbienceSystem` pausiert stumme Loops und spielt stumme Ereignisse gar nicht
  (`AudioCategories.effective_volume` = Kategorie × Eltern-Busse), das Atmen nach dem Sprint ebenso. Alte `settings.cfg` (ohne `meta/version` 2) bekommen den neuen
  Standard, wo noch der alte Wert 100 % steht; bewusst gesetzte Werte bleiben (`GameSettings.SETTINGS_VERSION`).

* **Ende der Runde (nicht überspringbar):** Letzter-Abschuss-Replay → Abspann → Scoreboard laufen ohne Leertaste-Skip (`Game._unhandled_input` schluckt sie). Die normale Killcam nach dem eigenen Tod
  bleibt überspringbar.
* **Kartenabstimmung als feste Choreografie** (`MatchEndScreen`, eine Uhr `NetworkManager.vote_time` = 20 s, kein vorzeitiges Ende mehr): *RESULTS* (10 s) Scoreboard (Siegerteam links, Verlierer rechts, K/D-Spalte) + kleine Karten unten;
  *FINAL* (5 s) Scoreboard blendet aus und schrumpft, die Karten (`VoteCard`) gleiten groß und auseinander in die Bildschirmmitte, großer Countdown, Abstimmung läuft weiter;
  *OUTCOME* (`vote_outcome_time` 2.8 s) die zwei anderen Karten verschwinden, die Gewinnerkarte zentriert sich, Blitz + Lichtstreifen, füllt den Bildschirm (dasselbe Bild wie der
  Ladebildschirm) → Host startet die Runde. Online: Host zählt (`_finish_vote` → `vote_closed(winner)` per RPC, Start erst nach `vote_outcome_time`); offline läuft dieselbe Abfolge lokal
  (eigene Wahl, ohne Wahl zufällig). Ohne Kartenabstimmung bleibt das Scoreboard bis zum Knopfdruck. Protokoll 6.
* **Granate halten:** G gedrückt (`PlayerInputState.grenade_held`, `HELD_GRENADE`) hält die gezogene Granate in der Wurfpose (`GRENADE_HOLD_T` 0.58, Hand zittert leicht), Loslassen wirft.
  Sprint: eine schon gehaltene Sprinttaste bricht Nachladen/Wurf nicht ab, ein neuer Druck schon (`Player._update_states`).
* **Fadenkreuz:** beim Sprinten Punkt + vier feine Striche, mit Granate in der Hand Punkt + Ring (gehalten: warm, pulsierend, vier Innen-Ticks).
* **Ego-Arme:** `FirstPersonArms` – Zwei-Knochen-IK von Schultern im Kameraraum zu den Handgelenken des Waffenmodells (streckt bei Bedarf), flach schattierte, verjüngte Achtkant-Gliedmaßen
  (Unterarm Hautton, Oberarm Hemd – wie die Figur). Die eingebauten Unterarm-Boxen des Ego-Modells sind ausgeblendet (`ReloadRig.show_sleeves`); Arme enden nie mitten im Bild (FOV 60–110).
* **Streuung MP5/AK:** Hüfte 2.9°/2.3° (vorher 2.4°/1.9°), Visier 0.35°/0.38° (vorher 0.2°/0.25°). Bei Dauerfeuer wächst `spread_bonus` (Pro-Schuss-Zuwachs
  größer als die Erholung je Schuss); im Visier wirkt er nur zu `Weapon.ADS_BLOOM` (0.4). Visier-Optik (`ads_position`, `ads_fov`) unverändert.
* **Schrotflinte nachladen:** Schaden 30 × 8 Schrot (Abfall 8–20 m, min. 6), Zyklus 0.44 s. `ReloadRig` (`shell_first`/`shell_last`): erste Patrone von Vorderschaft zum Gürtel,
  dann Gürtel ⇄ Ladeklappe (unten am Gehäuse) ohne Umweg, nur die letzte Patrone geht zurück zum Vorderschaft; Bewegungen als „Snap“-Flicks (`_key(..., snap)`),
  Waffe wird gekippt, ruckt beim Einschieben und federt zurück. Die Patrone zählt, sobald sie eingeschoben ist (`ReloadRig.SHELL_INSERT_T`), nicht erst am Zyklusende.
  Sound `shell_insert` = doppeltes „Ratsch-Ratsch“ (Ratsche + Schleifen + Klack; `tools/generate_audio.py`).
* **Lade-Abbruch per Schuss:** Feuern im Zustand `RELOADING` mit Patronen im Rohr → `Weapon.State.RELOAD_EXIT` (0.2 s, `ReloadRig.begin_exit()/blend_out()` blendet die Pose
  weich in die Ruhelage), der Schuss wird per `fire_queue_t`/`take_queued_fire()` vorgemerkt und danach genau einmal ausgelöst. Leeres Rohr: Schuss ohne Wirkung, Nachladen läuft weiter.
  Andere Maschinen: `WeaponManager.stop_tp_reload()` bzw. `play_remote_shot` beendet die Nachlade-Animation der Figur.
* **Endscreen:** `Scoreboard.side_by_side` (zwei Teamtabellen, Sieger links; `kd_text` = Kills/Tode mit 2 Nachkommastellen). Die Klassenwahl (`ClassStrip`: Bild, Name, Waffen, Schaden, Ausrüstung im HUD-Stil)
  erscheint erst in der Finalphase (`FINAL_VOTE_TIME` 10 s, = Hälfte der Gesamtzeit), Hauptmenü-Knopf und Klassenwahl mittig unten. Ohne Abstimmung bleibt die Klassenwahl unter dem Scoreboard.
* **Killcam-Hitmarker:** `HitFeedback` (Zeichnen + Sounds, von HUD und Killcam genutzt). Jeder Schuss trägt Trefferbits (`BODY`/`HEAD`/`KILL`) im Impact-Array (4. Eintrag) zu den anderen Maschinen;
  `Player.hit_flag` → `ReplayRecorder` speichert sie je Frame (Index 8) und meldet sie als `killer_hit` → `Game` zeichnet Hitmarker + spielt die Sounds in Killcam und Last-Kill-Cam.
* **Hände:** nackte Hände mit Fingergliedern, Knöcheln und Nägeln (`tools/generate_weapon_models.py`: `support_hand`/`grip_hand`); die Materialien `skin`/`skin_shade`/`nail` werden je Modell
  per `ReloadRig.apply_skin` auf den Hautton des Spielers gesetzt (gleich wie Ego-Arm und Figur).
* **Regler-Ton:** jeder Lautstärkeregler spielt `AudioManager.play_preview` = leises `kill_confirm` (−27 dB) auf dem Bus der Kategorie.
* **Nachladen (Magazinwaffen):** Hand- und Magazinbewegungen als „Snap“-Flicks, Rucke beim Herausreißen/Einschlagen des Magazins und beim Durchladen (`ReloadRig._pose_rifle/_pose_pistol`),
  Kamera-/Waffenstoß bei den harten Momenten (`Weapon.RELOAD_JOLTS`); Nachladezeiten AK 2.2 s, MP5 1.75 s, Pistole 1.5 s.
* **Blendgranate:** Taste F (`flashbang`, `HELD_FLASH`/`ACT_FLASH`, `PlayerInputState.flash_*`), gleiche Wurflogik wie die Granate (Splint, Halten, Loslassen) über
  `WeaponManager._grenade_kind`; `ClassData.flashbangs` (1). `Grenade.kind` (`KIND_FLASH`: Silberdose, Zünder 1.6 s); alle Maschinen spielen `Grenade.spawn_flash_fx` und feuern
  `GameEvents.flashbang_exploded`. `FlashMath` (Abstand 6–24 m, Blickrichtung, Sichtlinie gegen Wände) bestimmt die Stärke für den lokalen Spieler (`FlashOverlay`) und für Bots
  (`BotController._blind_left`: sehen und schießen nichts). `FlashOverlay`: Weißblende (max. 1.8 s) → unscharfes, aufgehelltes Bild + dunkles Nachbild (`assets/shaders/flash_blind.gdshader`),
  zusammen ca. 5.5 s; `AudioManager.set_flash_effect`: Tiefpass + Absenkung auf den Kategorie-Bussen (nicht HitOther/UI), Tinnitus `flash_ring`. Direkttreffer jeder Granate: 5 Schaden + Hitmarker (einmal pro Granate).
* **Sniper:** `WeaponData.bolt_action/scoped/scope_fovs/lower_body_*`, Klasse `class_sniper` (230 Schaden, Kopf 1.2×; unterhalb 55 % der Körperhöhe 0.5× → kein One-Hit-Kill).
  Repetieren nach jedem Schuss: `Weapon._update_bolt` (Verschluss dreht/gleitet, rechte Hand greift den Griff, Sounds `sniper_bolt_open/close`); währenddessen `WeaponManager.can_aim()` = false (Scope klappt weg, danach automatisch wieder an).
  Scope: `ScopeOverlay` (CanvasLayer 1) mit zweiter Kamera in einem `SubViewport` (gleiche Welt, `scope_fov`, ohne Viewmodel-Layer `1<<19`) + `assets/shaders/scope_view.gdshader` (Linse mit Absehen/Mil-Dots,
  außen die ungezoomte, stark weichgezeichnete Hauptansicht); Hauptkamera zoomt nicht (`WeaponData.effective_ads_fov`), Mausrad = Zoomstufe (`Weapon.zoom_step`), Maus-Empfindlichkeit skaliert mit dem Zoom.
  Killcam: `ReplayRecorder.killer_scope_fov()` → dieselbe Scope-Ansicht aus Sicht des Schützen. Bots wählen die Klasse nicht.
* **Match-Start-Countdown:** `MatchCountdown` (CanvasLayer 101): Menü/Lobby-Start (`GameDirector.start_match(cfg, true)`, online `host_start_match(cfg, true)` + RPC-Flag, Protokoll 8) zeigt 3-2-1 mit Kartenkarte,
  Flash/Glanz, dann wächst die Karte auf Vollbild und geht nahtlos in den Ladescreen über. Rundenneustart nach Voting nutzt ihn nicht.
* **Leben 250** (Anzeige in Prozent bleibt 100), Regeneration 112/s; Sniper 290, Granate max. 290 (One-Hit bleibt). Schrotflinte: 8×70, Abfall 14–28 m, Visier 1.8° (≈95 % One-Hit auf Oberkörper/Kopf bis ~12 m).
* **Schadens-Feedback (visuell):** `DamageFx` (CanvasLayer 1, vom HUD erzeugt) ersetzt Vignette/Damage-Flash/Blut-Layer des HUD. Ein Shader (`damage_screen.gdshader`): Treffer-Aufblitzen, dunkelrote blutig-schmutzige Ränder,
  unter 25 % Leben Tunnelblick, Entsättigung, chromatische Aberration, langsamer Puls (stärker je näher am Tod). Linsen-Splatter (prozedurale Texturen: Blobs, Schmieren, Spritzer, Dreck, Kratzer, Drips),
  FOV-Kick pro Treffer (kehrt von selbst zurück). Läuft nur, solange etwas aktiv ist; Heilung blendet kontrolliert aus, Respawn setzt sauber zurück. Nur Events (`local_player_damaged/health_changed/died/spawned`), Gameplay/Audio unberührt.
* **Dritte Person (Ansicht anderer Spieler):** `HumanoidRig` kennt jetzt Zielen (Waffe geschultert), Sprinthaltung (Waffe gesenkt/gekippt, `weapon_tilt`), Waffenwechsel-Absenken (`switch_pulse`),
  Schuss-Rückstoß (`shot_kick`), Treffer-Reaktion (`hit_react`: Oberkörper/Kopf je nach Richtung, Kopfschuss = Kopfruck), Landen (Knie geben nach), Beine drehen sich beim Seitwärts-/Rückwärtslaufen
  und einen Granatenwurf (Granate zünden, Ausholen hinter die Schulter, Wurf; Waffe ist währenddessen weg). Alles aus bereits synchronisierten Zuständen (Snapshot-Flags, Waffen-Events) bzw. dem neuen,
  gedrosselten Event `hit_react` (`NetworkManager.broadcast_hit_react`, Protokoll 9) - keine Animationsframes im Netz.
* **Ragdoll:** `Ragdoll` ersetzt beim Tod den Körper in derselben Pose durch 11 RigidBodies mit Generic6DOF-Gelenken (Knie/Ellbogen einseitig). Stoß weg vom Schützen je Waffe (`Player.DEATH_PUSH`), Kopfschuss
  Kopfschuss-Kill: der Kopf wird abgetrennt (ohne Gelenk, springt/rollt, schrumpft nach 5,5 s weg), Halsstumpf am Torso mit Blutfontäne; Granaten schleudern weg vom Explosionszentrum (`_last_damage_source`).
  Gore: `Player._pick_gore` wählt abgerissene Teile (Granate: 2-3 Glieder, 30 % alles; Schrotflinte/Sniper oft ein Glied nahe der letzten Trefferstelle; sonst selten). `Ragdoll` löst die Gelenke, setzt Stümpfe, pulsierende Blutspritzer (`_spurts`, auch am Boden), Fleischbrocken und eine wachsende Blutlache (`BloodFx.pool`). Die Killcams spielen denselben Tod nach (`Player.last_death` → `kill["death"]` im `ReplayRecorder` → `replay_set_alive`). Weltblut: feine Spritzer-Texturen (`BloodFx._make_texture`).
  schlägt den Kopf zurück, Explosionen werfen hoch. Nur Welt-Kollision (Layer 5), nach 4 s eingefroren, nach 9 s ausgeblendet, max. 8 gleichzeitig. Impulse erst nach den ersten Physik-Schritten (Massen).
* **Nachladehinweis:** `HUD._update_reload_hint` - „R ZUM NACHLADEN“ ab `RELOAD_HINT_FRACTION` (25 %, mind. 2 Schuss) des Magazins; leer = größer, rot, pulsierend; weg beim Nachladen/Wechseln/Granate.
* **Bot-Verhalten menschlicher (Schwierigkeitswerte unverändert):** Fadenkreuz wandert vom aktuellen Blick zum Gegner (kein Snap), folgt Bewegung mit kleinem Nachlauf, gedrosselte/geglättete Drehung,
  Zielfehler driftet, Kopf/Brust nur alle ~1 s neu gewählt, Reaktionszeit zufällig ±30 % plus Verzögerung bei Gegnern abseits der Blickachse; nach einem Kill kurze Pause; Kampfstile `HOLD/PUSH/FLANK`
  (Seitenroute über Deckungspunkte), Ausweichen und gelegentlich kurzer Rückzug bei Beschuss, Duck-Peeks, geglättetes Strafen, Seitenblicke beim Patrouillieren, ADS mit Hysterese.
