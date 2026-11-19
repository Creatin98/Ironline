# IRONLINE — DEVELOPMENT ROADMAP

## Project Vision

Ironline aims to become a highly polished, addictive, classic-era arcade FPS inspired by the strongest Call of Duty multiplayer experiences from World at War through Black Ops II.

The objective is to combine excellent gunplay, memorable maps, cinematic environments, professional presentation, responsive gameplay, and stable engineering into a distinctive standalone game.

The permanent creative and technical standards are defined in `CLAUDE.md`.

This roadmap defines development priorities and direction. It is not a rigid schedule. Claude may adjust implementation order when a better approach becomes apparent, provided the overall priorities and quality standards are respected.

---

# CURRENT PROJECT STATUS

The project already has a playable FPS foundation.

### Working foundation
- Core FPS gameplay.
- Movement and gunplay.
- Weapon handling and animations.
- Hitmarkers and hit feedback.
- Kill and headshot feedback.

These systems currently satisfy the user and should be preserved unless a concrete improvement is necessary.

### Areas requiring substantial improvement
- Three existing standard maps, one somewhat more developed than the others.
- Map layouts, level design, architecture and environmental composition.
- 3D assets, materials, textures and environmental detail.
- Lighting, atmosphere and cinematic presentation.
- HUD and menus.
- Overall visual identity and production quality.

**Important:** The visual target described in `CLAUDE.md` has not yet been achieved. The current project is the starting point for this roadmap, not a finished representation of the intended quality.

---

# PHASE 1 — FOUNDATION AND PROJECT QUALITY

**Priority: Critical**

Establish a reliable foundation for the major quality improvements.

- Inspect the current project state and identify relevant technical limitations.
- Preserve existing gameplay systems that already feel good.
- Verify project stability and existing functionality.
- Establish a consistent asset and scene organization.
- Establish a reliable Blender-to-Godot workflow where appropriate.
- Identify useful free tools that can materially improve production quality.
- Ensure future implementations remain performance-conscious and multiplayer-ready.

**Completion goal:** A stable, well-organized foundation for the visual and content overhaul.

---

# PHASE 2 — FLAGSHIP MAP OVERHAUL

**Priority: Highest**

Transform the strongest existing map into a showcase-quality Ironline multiplayer map.

- Rework weak or illogical map layouts.
- Create memorable architecture and recognizable landmarks.
- Improve lanes, routes, flanking opportunities and combat spaces.
- Balance close-, medium- and long-range engagements.
- Improve spawn logic, cover and sightlines.
- Create convincing buildings, interiors, streets and environmental structures.
- Introduce high-quality original Blender assets and procedural content.
- Improve materials, textures, lighting, atmosphere and environmental storytelling.
- Validate the map from actual first-person gameplay.
- Iterate until the result is both visually impressive and genuinely fun to play.

**Completion goal:** At least one exceptional, polished reference map that establishes the quality standard for all future Ironline maps.

---

# PHASE 3 — REMAINING MAPS

**Priority: High**

Bring the remaining maps up to the established flagship standard.

- Reassess each map's layout and gameplay flow.
- Rebuild weak areas rather than merely decorating bad geometry.
- Give each map its own identity, atmosphere and architectural language.
- Avoid repetitive layouts and copy-pasted environments.
- Maintain balanced gameplay and clear navigation.
- Prioritize quality over map quantity.

**Completion goal:** A small collection of distinctive, polished and replayable multiplayer maps.

---

# PHASE 4 — VISUAL PRODUCTION PIPELINE

**Priority: High**

Develop a reusable production workflow for consistently high-quality content.

- Blender modeling and modular environment kits.
- Original props, architecture and environmental assets.
- Procedural modeling and material generation where useful.
- PBR material standards.
- Efficient collision meshes and LODs.
- Decals, surface wear and environmental variation.
- Consistent import settings and asset organization.
- Reusable shaders and visual effects.
- Performance-aware scene construction.

Claude should independently discover and recommend tools that meaningfully raise the quality ceiling. Ask the user before installing unfamiliar software or making significant changes to the environment.

**Completion goal:** A repeatable pipeline capable of producing professional-quality Ironline content without requiring the user to manually source environment assets.

---

# PHASE 5 — HUD, MENUS AND PRESENTATION

**Priority: High**

Replace generic or unfinished interface elements with a cohesive premium FPS experience.

- Establish a distinctive Ironline interface identity.
- Redesign the HUD.
- Improve typography, icons, spacing and visual hierarchy.
- Create polished menus and transitions.
- Organize settings professionally.
- Improve graphics, audio and gameplay settings interfaces.
- Ensure responsive behavior across supported resolutions.
- Maintain excellent readability during combat.

**Completion goal:** HUD and menus that feel like part of a finished, premium FPS.

---

# PHASE 6 — AUDIO AND CINEMATIC POLISH

**Priority: Medium to High**

Refine the audiovisual experience while preserving successful existing feedback.

- Improve environmental ambience.
- Refine sound mixing and spatial audio.
- Keep weapon and feedback sounds satisfying.
- Prepare flexible systems for replacing audio assets.
- Improve environmental particles and effects.
- Add appropriate environmental motion.
- Refine lighting, atmosphere and post-processing.
- Improve transitions and presentation throughout the game.

**Completion goal:** A coherent, immersive and satisfying audiovisual identity.

---

# PHASE 7 — OFFLINE GAMEPLAY EXPERIENCE

**Priority: Critical**

Make the offline game feel complete, polished and highly replayable.

- Refine match flow and game modes.
- Improve bots and offline match behavior where applicable.
- Ensure weapons and combat remain satisfying.
- Improve menus, match transitions and results presentation.
- Polish spawning, scoring and match pacing.
- Identify and eliminate frustrating or unfinished gameplay details.

**Completion goal:** An excellent standalone offline FPS experience that is enjoyable beyond short testing sessions.

---

# PHASE 8 — PERFORMANCE AND RELEASE PREPARATION

**Priority: Critical before release**

- Profile real gameplay performance.
- Optimize maps, meshes, textures, materials and lighting.
- Improve loading and scene transitions.
- Test different graphics settings.
- Check stability across longer sessions.
- Validate Windows builds.
- Fix critical bugs and regressions.
- Ensure the game remains responsive and visually consistent.

**Completion goal:** A stable, optimized Windows build with consistent performance and professional presentation.

---

# PHASE 9 — MULTIPLAYER DEVELOPMENT

**Priority: Long-term**

The project must remain multiplayer-ready throughout development, but the immediate priority is the offline experience.

When the offline foundation is sufficiently polished:

- Review and finalize multiplayer architecture.
- Implement robust host/server authority.
- Develop reliable player synchronization.
- Implement matchmaking or server discovery as appropriate.
- Validate latency handling and hit registration.
- Ensure weapons, damage, scoring and match state are authoritative.
- Test multiplayer performance and stability.
- Polish the complete online match experience.

**Completion goal:** A robust, satisfying multiplayer FPS experience built on the existing Ironline foundation.

---

# DEVELOPMENT RULES

1. `CLAUDE.md` is the permanent source of truth for creative, technical and quality standards.
2. This roadmap defines priorities, not rigid implementation restrictions.
3. Claude has broad creative and technical freedom within the project vision.
4. Do not wait for the user to specify every implementation detail.
5. Do not sacrifice quality simply to complete phases quickly.
6. Preserve existing systems that already work well.
7. Every major visual implementation must be inspected in-engine.
8. Test changes appropriately and report honestly.
9. Keep performance and future multiplayer compatibility in mind.
10. Keep user-facing communication concise and spend development effort on implementation.

## Guiding Principle

**Build fewer things exceptionally well rather than many things poorly.**

Ironline should not merely become a playable shooter. It should become a distinctive, polished and genuinely addictive classic-style FPS that feels carefully crafted in every detail.
