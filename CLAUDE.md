# IRONLINE --- MASTER PROJECT DIRECTIVE

## Permanent vision, creative authority, engineering standards, and quality rules

**This document is the standing source of truth for the direction and
quality bar of Ironline.** Read it at the beginning of every substantial
task and use it as the framework for all future implementation
decisions. Do not require the user to repeat these goals.

------------------------------------------------------------------------

# 1. THE PROJECT

Ironline is an ambitious, fast, satisfying, classic-style multiplayer
first-person shooter being developed in Godot 4.7 with GDScript.

The goal is not to make a generic indie shooter, a tactical military
simulator, a battle royale, or a technically impressive prototype with
mediocre presentation. The goal is to create a genuinely compelling,
highly polished, addictive arcade FPS with the immediate readability,
pace, responsiveness, map flow, audiovisual feedback, and replayability
associated with the strongest Call of Duty multiplayer games.

The intended reference era is primarily:

-   Call of Duty: World at War
-   Modern Warfare 2 (2009)
-   Black Ops
-   Modern Warfare 3 (2011)
-   Black Ops II

These games are references for **feel, pacing, readability, atmosphere,
presentation, map flow, weapon identity, and multiplayer
intensity**---not assets, names, maps, branding, or content to copy.
Ironline must have its own identity.

The desired result should feel like a lost, exceptionally well-made
classic-era premium FPS: familiar in its immediate fun and clarity, but
with a distinctive world, modern technical execution, attractive
contemporary rendering, and carefully crafted detail.

The user is an experienced player and technology enthusiast, but not a
programmer or level designer. Do not expect the user to design systems,
write code, model assets, research tools, or micromanage implementation.
Your role is to turn the vision into a working, beautiful game.

# 2. CURRENT PROJECT STATE --- READ THIS CAREFULLY

**Do not mistake the target vision for the current state. The game has
NOT reached the visual or content quality described in this document.**

At the time this directive was written:

-   The project already has a playable FPS foundation.
-   Core gameplay and gunplay are in a good state.
-   Movement, weapon handling, hitmarkers, kill feedback, headshot
    feedback, and weapon animations are currently satisfying to the
    user.
-   These successful systems must be protected. Do not casually rewrite,
    regress, or destabilize them.
-   The game is still visually unfinished and does not yet look like the
    intended premium-quality shooter.
-   There are currently three standard maps. One map (referred to by the
    user as "Masa" or a similar name) is somewhat more developed than
    the others, but it still needs a substantial redesign and quality
    upgrade.
-   The maps, environments, architecture, visual composition, materials,
    lighting, atmosphere, HUD, menus, and overall presentation are not
    yet at the desired level.
-   The game has not suddenly become cinematic, richly detailed, or
    professionally art-directed simply because this document describes
    that goal.

Treat the existing project as a functioning foundation---not a finished
product. The first major objective is to raise the current game to the
quality bar in this directive.

When inspecting the project, establish the actual current implementation
from the files and running game. Do not assume that a feature exists
just because it is mentioned here. Do not invent progress or claim
visual improvements that have not been implemented and checked.

# 3. THE NORTH STAR

Build a game that is:

-   Immediately fun and satisfying to play.
-   Fast, responsive, readable, and unmistakably arcade-oriented.
-   Visually distinctive, cinematic, atmospheric, and coherent.
-   Built around excellent maps that create memorable matches.
-   Rich in environmental detail without visual clutter.
-   Consistent in quality across maps, weapons, UI, menus, effects, and
    audio.
-   Stable, optimized, and maintainable.
-   Designed offline-first during the current development focus, while
    preserving sound multiplayer architecture for the future.

The user wants **quality, not quantity**. A small number of exceptional
maps is better than a large collection of generic maps. A few highly
polished features are better than many mediocre systems.

Do not settle for "it works." The standard is "it works, feels
excellent, looks intentional, and has been tested."

# 4. CREATIVE AUTHORITY AND AUTONOMY

You have broad creative freedom inside the Ironline vision.

The user explicitly wants you to make decisions independently in areas
where they do not have specialist knowledge. This includes, but is not
limited to:

-   Art direction and visual composition.
-   Environment and architectural design.
-   Map layout and encounter design.
-   Blender workflows and 3D asset creation.
-   Procedural modeling and procedural environment generation.
-   Materials, shaders, lighting, atmosphere, and post-processing.
-   VFX, environmental animation, and visual polish.
-   HUD, menus, typography, iconography, and interface behavior.
-   Technical implementation choices and appropriate tools.
-   Performance improvements and workflow improvements.

Do not ask the user to make every small decision. Do not repeatedly ask
what style, building, prop, material, light, or effect should be used
when the project vision already gives you enough direction.

Use professional judgment. Make a decision, implement it, inspect the
result, and improve it.

## 4.1 When to ask the user

Ask briefly before proceeding when:

-   A tool, application, engine extension, plugin, or dependency needs
    to be installed or enabled on the user's machine.
-   A proposed workflow requires a meaningful new external tool or a
    change to the user's environment.
-   An action has a significant cost, account requirement, subscription,
    license obligation, security implication, or irreversible
    consequence.
-   A major creative or gameplay decision would fundamentally change the
    identity or direction of Ironline.
-   You need information or a file that cannot reasonably be obtained or
    generated independently.

When asking, explain in a few concise sentences: 1. What tool or
decision is involved. 2. Why it would materially improve Ironline. 3.
Whether it is free and what installation or setup is required.

Do not ask permission for ordinary implementation decisions, routine
code changes, procedural asset creation, or normal iteration within the
existing project.

If a proposed tool would substantially raise the quality ceiling,
discover it yourself and bring it to the user's attention. Do not ignore
powerful workflows simply because the user has not named the tool.

# 5. VISUAL IDENTITY AND ART DIRECTION

## 5.1 Target aesthetic

The target is premium classic-era Call of Duty presentation, elevated
with modern rendering and production quality.

Aim for:

-   Believable, grounded military and contemporary environments.
-   Strong architectural identity and memorable silhouettes.
-   Rich but controlled color grading.
-   Convincing materials and surface response.
-   Dramatic, motivated lighting.
-   Atmospheric depth and cinematic composition.
-   Carefully placed environmental storytelling.
-   Detailed props and set dressing.
-   Clear gameplay readability at normal combat distances.
-   A cohesive visual language across all maps and interfaces.

The game should look intentionally art-directed---not like a random
collection of downloaded assets or procedural objects.

## 5.2 Explicitly avoid

Do not drift into:

-   Low-poly or primitive-looking environments.
-   Greybox presentation as a final result.
-   Generic rectangular arenas and repetitive box-shaped buildings.
-   Flat, empty, sterile, or uniformly lit maps.
-   Repeated buildings and props with obvious copy-paste placement.
-   Cheap-looking materials, excessive flat colors, or placeholder
    textures.
-   Excessive bloom, fog, chromatic aberration, lens effects, or
    post-processing.
-   Overly futuristic sci-fi styling unless a specific, coherent design
    calls for it.
-   Hyper-realistic tactical milsim aesthetics that undermine arcade
    readability.
-   Visual clutter that obscures opponents or makes combat unfair.
-   Random detail added without architectural, gameplay, or
    environmental purpose.

Modern technology should improve the classic FPS identity, not erase it.

# 6. ASSET CREATION --- BLENDER AND BEYOND

The user does not want to manually search for, download, sort, or
provide large collections of environment assets. **Take responsibility
for producing the assets and environment content.**

## 6.1 Preferred asset workflow

Prefer, in this order:

1.  Original assets modeled specifically for Ironline.
2.  Blender-created modular architecture, props, weapons-related
    environment pieces, and set dressing.
3.  Procedural meshes, geometry, textures, materials, decals, and
    environmental variation.
4.  Free, legally usable assets from trustworthy sources when they
    materially improve quality and can be integrated without burdening
    the user.

Do not make the user hunt for assets or follow long manual
asset-gathering instructions. Do not assume the user will provide
models, textures, or map pieces.

## 6.2 Blender is an encouraged tool

Blender is a major potential part of the Ironline production pipeline.
Be proactive about using it when it offers a meaningful quality
improvement.

Explore and use suitable Blender workflows for:

-   Modular building kits.
-   Complete building exteriors and interiors.
-   Architectural details and structural variation.
-   Roads, sidewalks, walls, barriers, fences, and terrain elements.
-   Vehicles, wreckage, street furniture, industrial props, and debris.
-   Optimized collision meshes.
-   UV mapping and texture preparation.
-   LODs and mesh optimization.
-   Procedural geometry and repeatable asset generation.
-   Export pipelines suitable for Godot.

If Blender is not installed or cannot be used, do not silently abandon
the possibility. Explain briefly why it would be valuable, ask whether
the user approves installation or setup, and proceed with an appropriate
alternative until approved.

The same principle applies to other useful tools: discover them
yourself, explain their value concisely, and ask before installing or
making significant environment changes.

## 6.3 Asset quality standards

All custom or imported assets must meet a consistent professional
standard:

-   Correct scale and believable proportions.
-   Clean topology and sensible mesh complexity.
-   Appropriate UVs and texture density.
-   PBR materials where appropriate: albedo/base color, roughness,
    metallic, normal, ambient occlusion where useful.
-   Convincing material differentiation: concrete should not look like
    painted plastic; metal, glass, wood, asphalt, fabric, and masonry
    must read distinctly.
-   Realistic edge treatment and structural detail where visible.
-   No unnecessary geometry or oversized textures.
-   Proper collision separate from high-detail render meshes where
    appropriate.
-   Sensible naming, organization, origins, pivots, and reusable modular
    dimensions.
-   Correct Godot import settings and tested in-engine appearance.

Do not create a detailed asset that looks good in Blender but looks
wrong, too dark, too shiny, too flat, or incorrectly scaled in Godot.
Always inspect it in the actual game environment.

## 6.4 Licensing and cost

-   Prefer free tools and free assets with clear licenses.
-   CC0 and public-domain assets are preferred when external assets are
    necessary.
-   Never use paid assets, subscriptions, paid APIs, or services that
    create unexpected costs without explicit approval.
-   Never bypass licensing or use assets with unclear rights.
-   Do not require accounts, logins, API keys, or user subscriptions
    unless the user explicitly approves.
-   Keep third-party assets organized and record their source and
    license.

# 7. MAP DESIGN --- A TOP PRIORITY

The current maps are not at the desired quality level. Their layouts and
visual construction need serious attention. Do not treat the existing
three standard maps as finished content.

The user wants maps that feel like carefully designed classic Call of
Duty multiplayer maps: instantly understandable, exciting to learn,
balanced, visually memorable, and consistently fun across repeated
matches.

## 7.1 Map design principles

Every map must have:

-   A clear and memorable identity.
-   A coherent setting and believable spatial logic.
-   Strong landmarks and recognizable silhouettes.
-   Carefully designed routes and combat spaces.
-   Meaningful choices between lanes, routes, cover, and flanking
    opportunities.
-   A considered balance of close-, medium-, and long-range engagements.
-   Controlled sightlines rather than accidental map-wide exposure.
-   Fair spawn areas and sensible spawn logic.
-   Multiple viable routes without confusing or meaningless complexity.
-   Cover that makes spatial and tactical sense.
-   Interesting transitions between interiors and exteriors.
-   Verticality only where it contributes to the map.
-   A strong visual composition from the player's actual first-person
    perspective.

Layouts should be organic and architecturally plausible. Avoid maps made
from disconnected boxes, repetitive corridors, arbitrary open spaces,
and buildings that exist only as simple cover blocks.

## 7.2 Environmental construction

Build complete-feeling places, not merely playable geometry.

Examples of appropriate detail, when relevant to the setting:

-   Buildings with distinct architectural character.
-   Varied rooflines, facades, entrances, windows, balconies, and
    structural depth.
-   Roads, curbs, sidewalks, drainage, markings, and believable
    transitions.
-   Vehicles, barriers, street furniture, signs, cables, pipes, vents,
    and utility infrastructure.
-   Interior rooms with purposeful layouts and convincing details.
-   Damage, wear, dirt, weathering, rubble, and environmental
    storytelling.
-   Vegetation and natural variation where appropriate.
-   Layered backgrounds and distant silhouettes to create depth.
-   Subtle environmental motion such as flags, foliage, smoke, dust, or
    loose elements.

Every detail should support the environment's story, visual quality, or
gameplay readability. Do not add clutter just to increase object count.

## 7.3 Quality over map count

Do not rush to create more maps while existing maps remain mediocre.

Prioritize transforming the strongest existing map into a genuinely
impressive reference-quality Ironline map. Then use the same standards
to rebuild or substantially improve the remaining maps.

Preserve a working fallback or backup before major map changes. Do not
destroy the playable project while pursuing visual quality.

## 7.4 First-person validation

A map is not finished because it looks good in an editor or top-down
view.

Inspect it at player height and normal gameplay speed. Check:

-   Actual sightlines and visibility.
-   Scale of doors, rooms, stairs, cover, and props.
-   Whether players can read the space while moving.
-   Whether geometry creates accidental head glitches or unfair angles.
-   Whether routes and flanks work in real matches.
-   Whether collision matches visible geometry.
-   Whether spawns are safe and sensible.
-   Whether detail creates visual noise or performance problems.

Iterate until the map feels deliberately designed and enjoyable to play.

# 8. LIGHTING, MATERIALS, ATMOSPHERE, AND CINEMATIC PRESENTATION

This is a major quality requirement, not optional decoration.

Use lighting and atmosphere to give each map a strong mood and visual
identity.

Consider:

-   Directional sunlight and believable shadowing.
-   Interior and exterior lighting contrast.
-   Practical light sources that appear to illuminate their
    surroundings.
-   Ambient fill that preserves visibility.
-   Atmospheric depth and carefully controlled fog.
-   Dust, smoke, haze, and environmental particles where appropriate.
-   Subtle volumetric effects only where they are efficient and
    justified.
-   Reflections and material response appropriate to the surface.
-   Decals, grime, weathering, and surface variation.
-   Carefully tuned exposure, color grading, and contrast.

The result should be cinematic and beautiful while remaining readable
during fast combat. Do not sacrifice opponent visibility or gameplay
clarity for screenshots.

# 9. HUD, MENUS, AND USER EXPERIENCE

The current HUD and menus are part of the visual overhaul. They must not
remain generic placeholders while the environments are improved.

Design a cohesive, premium FPS interface with a clear Ironline identity.

Standards:

-   Strong typography and consistent hierarchy.
-   Deliberate spacing, alignment, sizing, and visual rhythm.
-   Clear information priority during combat.
-   Crisp icons and consistent iconography.
-   Thoughtful animation and transitions.
-   Consistent colors, panels, borders, and visual language.
-   Professional settings organization.
-   Responsive scaling for supported resolutions and aspect ratios.
-   Readability at normal play distance and in motion.
-   No unnecessary decoration that competes with gameplay.

The HUD should feel like it belongs to a finished classic-style premium
shooter. Menus should feel polished, responsive, and coherent with the
game world.

Settings should be grouped logically. Graphics, sound, and
gameplay/interface settings should be clearly separated where
appropriate. Relevant FPS settings such as HUD, FOV, sensitivity, and
other player preferences must be easy to find.

Do not make a visually elaborate interface that is awkward to navigate.
Usability and visual quality must work together.

# 10. GAMEPLAY AND GUNPLAY --- PROTECT WHAT ALREADY WORKS

The user currently likes the core gameplay feel. Treat that as a
valuable foundation.

Preserve unless there is a demonstrated problem:

-   Movement responsiveness and feel.
-   Weapon handling and firing behavior.
-   Weapon animations.
-   Hitmarker feedback.
-   Kill confirmation feedback.
-   Headshot feedback.
-   Existing satisfying combat timing and effects.

Do not rewrite successful systems merely to make the code look cleaner.
Do not introduce regressions while working on visual systems.

When changes to gameplay are necessary:

1.  Identify the concrete issue.
2.  Keep the change as narrow as possible.
3.  Preserve the existing feel.
4.  Test it in actual play.
5.  Compare against the previous behavior.

The goal is to elevate the whole game without losing the satisfying core
that already exists.

# 11. AUDIO AND FEEDBACK

The user is attentive to sound quality and may replace selected sounds
with external sound effects. Keep the audio pipeline flexible and
organized.

Preserve sounds and feedback that already work well. Improve
implementation where useful:

-   Consistent loudness and mixing.
-   Clear separation of weapon, impact, hitmarker, kill, headshot, UI,
    ambience, and music layers.
-   Correct spatialization and attenuation.
-   Appropriate timing and transient clarity.
-   Strong but controlled low-frequency impact.
-   No clipping, harshness, or unnecessarily fatiguing effects.
-   Sound settings that work predictably.

Avoid placeholder-like or comical feedback where the intended tone is
premium military arcade FPS. A kill sound should feel decisive and
satisfying, not like a generic reward chime.

Do not spend time replacing audio assets the user intends to replace
manually unless asked. Make the system ready for clean asset swaps.

# 12. PERFORMANCE, OPTIMIZATION, AND STABILITY

Visual ambition must not produce an unplayable game.

Every implementation must be designed with performance in mind from the
beginning---not optimized only after it becomes a problem.

Pay attention to:

-   Draw calls and material count.
-   Mesh and texture memory.
-   Polygon count and overdraw.
-   Lighting and shadow cost.
-   Particle counts and transparency.
-   Physics and collision complexity.
-   Navigation and AI costs where relevant.
-   Scene-tree and script overhead.
-   Asset loading and scene transitions.
-   LODs, visibility ranges, and occlusion opportunities.
-   Appropriate reuse of materials and meshes.
-   Frame-time consistency, not just average FPS.

Use profiling and actual measurements when available. Do not guess that
something is optimized.

Maintain a practical visual-quality/performance balance for the intended
target hardware. The game should remain responsive and stable at normal
gameplay resolutions and settings.

Never use expensive visual effects indiscriminately. Every expensive
feature must justify its cost.

# 13. MULTIPLAYER-READY ENGINEERING --- EVEN DURING OFFLINE DEVELOPMENT

The immediate development focus is an excellent offline experience.
However, Ironline is intended to become a multiplayer FPS.

Therefore, every new system must be designed with future multiplayer
compatibility in mind.

-   Keep gameplay logic separated from presentation where practical.
-   Keep authority and ownership rules explicit.
-   Do not build systems that depend on every client independently
    deciding authoritative game outcomes.
-   Damage, kills, scoring, and other authoritative outcomes must remain
    server/host controlled.
-   Avoid hidden dependencies on local-only state.
-   Keep player identity, match state, weapons, spawns, and events
    structured for network use.
-   Avoid unnecessary tight coupling between UI, world logic, and
    network logic.
-   Ensure visual effects can be triggered from replicated gameplay
    events when needed.
-   Do not introduce architecture that would require a complete rewrite
    to support multiplayer.

Do not over-engineer speculative multiplayer infrastructure at the
expense of the current offline game. The standard is sensible
multiplayer-ready design, not premature complexity.

Use the existing authority patterns and project architecture. In
particular, use `MatchManager.is_authority()` and
`NetworkManager.is_host()` where appropriate. Never move authoritative
damage or kill decisions to clients.

# 14. GODOT AND CODE QUALITY RULES

The project uses **Godot 4.7 and GDScript**. Follow the actual project
conventions and existing architecture.

Mandatory principles:

-   Inspect the relevant files before changing them.
-   Read `README.md` for project orientation when needed.
-   Read `docs/ARCHITECTURE.md` when the task touches architecture or
    when understanding dependencies is necessary.
-   Work only in relevant files.
-   Do not perform whole-project audits for small tasks.
-   Do not rewrite systems without a clear reason.
-   Prefer minimal, targeted, maintainable changes.
-   Preserve existing behavior unless the task explicitly changes it.
-   Avoid duplicate systems and unnecessary abstractions.
-   Keep naming, organization, and code style consistent.
-   Handle errors and missing resources safely.
-   Avoid fragile hard-coded paths and unexplained magic values.
-   Do not leave dead code, temporary debug behavior, or broken
    placeholders.
-   Do not claim that code works without testing it.

Known GDScript/project pitfalls:

-   Lambdas capture scalar values by value; use a `Dictionary` or
    another appropriate reference container when a mutable counter must
    be shared.
-   Navigation queries must wait for navigation readiness using
    `BlockMap.wait_navigation_ready()` where relevant.
-   Authority decisions must use the established project methods rather
    than ad hoc assumptions.
-   Damage and kill outcomes must never be decided authoritatively on
    clients.

Do not change project-wide conventions casually. If a convention
genuinely needs to change, explain the reason briefly and migrate
consistently.

# 15. DEVELOPMENT WORKFLOW --- IMPLEMENT, INSPECT, ITERATE

The user wants tangible progress, not long discussions about what could
be done.

For substantial tasks:

1.  Briefly identify the intended result and the relevant implementation
    area.
2.  Make a concise plan internally; show only a short plan when it helps
    the user.
3.  Implement the actual work.
4.  Run the appropriate validation and tests.
5.  Launch or inspect the result when visual changes are involved.
6.  Identify defects and shortcomings.
7.  Iterate and improve before declaring the task complete.
8.  Report only the meaningful result, tests, and any remaining
    limitations.

For visual work, the first implementation is not automatically the final
implementation. Inspect the result in-engine, in the intended camera
perspective and at a realistic resolution. Fix obvious problems before
stopping.

Do not stop at a functional first pass when the task is explicitly about
visual quality. The quality bar is the reason for doing the work.

## 15.1 Visual quality review

For map, environment, lighting, UI, and asset tasks, evaluate:

-   Does it look like a coherent premium FPS?
-   Does it match the Ironline art direction?
-   Are proportions and materials believable?
-   Is there enough visual depth and variation?
-   Are there obvious repeated or placeholder elements?
-   Is the composition intentional?
-   Is it readable during actual gameplay?
-   Does it perform acceptably?
-   Does it match the quality of the best parts of the project?

If the answer is no, improve it before calling it finished.

# 16. TESTING AND VALIDATION

Use the project's existing validation workflow. Do not run every
expensive test for every tiny change; select tests based on what
changed.

Typical commands:

``` bash
python3 tools/validate_project.py
```

Godot headless import:

``` bash
godot --headless --path . --import --quit
```

Smoke test:

``` bash
godot --headless --path . tests/smoke_test.tscn
```

Visual snapshots:

``` bash
tools/shots/run.sh <godot> <ziel> <out.png> [WxH]
```

Network tests, only when changing networking, player authority, weapons,
damage, or related behavior:

``` bash
python3 tools/run_net_test.py <godot>
```

The network test can take approximately two minutes. Do not run it
without a relevant reason.

For visual tasks, use screenshots or direct in-engine inspection where
available. Headless validation alone cannot prove that a map, menu, or
effect looks good.

If a test cannot be run, state that plainly. Never fabricate test
results.

# 17. GIT AND PROJECT SAFETY

The project uses the following branch rules:

-   `main` is the active development branch.
-   `sicherheitskopie` is a fixed rollback/safety branch. **Never modify
    it.**
-   Do not create other branches unless explicitly requested.
-   Before risky changes, ensure there is a recoverable state.
-   After a completed phase, commit and push according to the existing
    project workflow.
-   Include the system-required `Co-Authored-By` line in commits.
-   Do not commit broken, untested, or unrelated work.
-   Keep commits focused and meaningful.

Do not overwrite or delete existing user work. Do not perform
destructive cleanup without understanding its consequences.

# 18. TOKEN, TIME, AND COMMUNICATION EFFICIENCY

The user wants Claude's available usage to go into building the
game---not excessive conversation.

Therefore:

-   Be concise in user-facing responses.
-   Do not repeat the project vision in every response.
-   Do not produce long audits unless requested or genuinely necessary.
-   Do not narrate every file you open or every routine action.
-   Do not ask questions whose answers can be determined from the
    project.
-   Do not create unnecessary agents or parallel tasks.
-   Do not repeatedly restate plans.
-   Do not spend tokens generating elaborate proposals instead of
    implementing the requested work.
-   Avoid redundant searches and unnecessary tool calls.
-   Prefer direct implementation and concise reporting.

However, efficiency must never become an excuse for low quality. Spend
the necessary effort on implementation, testing, visual inspection, and
iteration. Save tokens by eliminating overhead---not by skipping
important work.

When you have a genuinely important idea that could materially improve
Ironline, mention it briefly. The user is open to strong suggestions. Do
not overwhelm them with a long list of speculative ideas.

# 19. DECISION-MAKING PRIORITIES

When choosing between competing approaches, prioritize in this order:

1.  The intended Ironline player experience and overall vision.
2.  Gameplay quality, readability, fairness, and responsiveness.
3.  Visual and audiovisual quality.
4.  Stability and maintainability.
5.  Performance.
6.  Future multiplayer compatibility.
7.  Development speed and implementation convenience.

Do not choose an easier implementation if it clearly compromises the
intended quality and a reasonable better solution exists.

Do not add complexity for its own sake. A sophisticated workflow is
justified when it creates a materially better game or a more reliable
production process.

# 20. WHAT "DONE" MEANS

A task is not complete merely because:

-   The project imports.
-   The scene opens.
-   A mesh exists.
-   A map is technically playable.
-   A menu has buttons.
-   A shader compiles.
-   A screenshot can be produced.

A task is complete when it meets the requested functional and quality
requirements, has been validated appropriately, and does not introduce
avoidable regressions.

For visual work, "done" additionally means that the result has been
inspected in-engine and is coherent with the intended art direction. If
there are obvious placeholder elements, broken proportions, flat
lighting, repetitive assets, poor composition, or severe readability
issues, it is not finished.

Be honest about what was and was not tested.

# 21. LONG-TERM DEVELOPMENT DIRECTION

The long-term goal is a polished, addictive, classic-style FPS with:

-   A distinctive Ironline identity.
-   A small collection of outstanding multiplayer maps.
-   Excellent weapon feel and combat feedback.
-   Beautiful, coherent environments.
-   Strong lighting, atmosphere, and environmental detail.
-   Professional HUD and menus.
-   Cohesive sound design and audiovisual feedback.
-   Stable performance.
-   Clean, maintainable, multiplayer-ready foundations.
-   A satisfying offline experience that can later grow into a robust
    multiplayer game.

The current priority is to make the existing offline game genuinely
impressive. Do not let future multiplayer ambitions become an excuse to
postpone the visual and gameplay quality of the present build.

------------------------------------------------------------------------

# 22. FINAL NON-NEGOTIABLE DIRECTIVE

**Do not merely maintain Ironline. Raise its standard.**

The current game is a foundation. The user expects a substantial leap in
quality from this point forward.

Take ownership of the creative and technical work. Make strong
decisions. Discover useful tools. Create original assets. Use Blender
and procedural workflows when they improve the result. Rebuild weak
maps. Give the environments architectural identity, depth, lighting,
atmosphere, and detail. Bring the HUD and menus to a coherent premium
standard. Protect the gameplay systems that already feel good. Keep the
project stable, optimized, and multiplayer-ready.

Do not wait for the user to describe every building, prop, shader, menu
panel, route, or technical solution. The vision and quality bar are
defined here. Use your expertise to realize them.

**Do not confuse "playable" with "finished." Do not confuse "more
detailed" with "better." Do not confuse "technically implemented" with
"high quality."**

Work autonomously within this directive. Ask only when a genuinely
important decision, installation, cost, or missing input requires the
user's involvement. Keep communication short. Put the effort into the
game.

**Ironline must become the game this document describes---not just a
project that contains this document.**
