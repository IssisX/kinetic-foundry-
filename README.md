# Kinetic Foundry — Vertical Slice 0.4

Godot 4.7 source-first rebuild for Android/mobile.

## Implemented in this slice

- Pulled-back third-person camera.
- Title, pause, and options with a view-law panel.
- Touch joystick + right-side look input.
- Character-relative attack/grab/use intent.
- Faces, a spine, and hips that counter-rotate while walking.
- Crew with different faces, box torsos, and no hat-brim facemask.
- Crew hold posts. Machines work their station. They do not shadow the player.
- Adaptive target commitment during combat/grapples.
- Enemy pursuit and attacks once the player enters range or lands a hit.
- Enemy-held excavator and dozer that can be hijacked.
- Player-driven excavator, crane, and tracked dozer.
- Direct boom/stick/tool, slew/luff/hoist, and blade/ripper control.
- Excavator impacts, crane suspended loads, dozer blade shove.
- Earth as a load: blade and bucket cut-and-pile walkable spoil.
- People as loads: machine mass writes crush and limp.
- Stress overlay, deformation, and damage skin — on or off in options.
- Four-support structural frame with progressive failure.
- Falling deck becomes persistent physics geometry.
- Procedural visuals: no external asset dependency.

## Desktop fallback controls

- WASD: move / drive.
- Mouse or right stick: look / working assembly.
- J: attack / drop blade.
- K: grab / ripper.
- R / F: raise / lower blade (dozer).
- E: use / enter / exit machine.
- P or Esc: pause. Enter: leave the title screen.

Touch is the primary target. Desktop input exists for quick verification.

## Pinned engine

Run the project through `./tools/godot --path .`. The wrapper installs the
pinned Godot 4.7 build once into a reusable cache, then delegates all
arguments to it. Set `KINETIC_GODOT_HOME` to share that cache across
checkouts.
