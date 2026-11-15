# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A family-friendly space roguelike made in **Godot 4.7** (GDScript, 4-space indentation) for the NASA Space Apps hackathon. Nobody ever dies: when crew members hit their health or stress limit, they fly home in the return capsule. A failed launch scrubs on the pad or parachutes into the sea, and the player goes back to planning.

There is no build step and no test suite. Changes are checked by running scenes.

## Commands

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

# Open the editor
open -a /Applications/Godot.app --args -e --path "$PWD"

# Run a scene headless (autoloads are included), e.g. to catch script errors
$GODOT --headless --path . --quit-after 600 res://scenes/mission_phase/mission_phase.tscn

# Run a throwaway test script (extends SceneTree, must call quit()).
# In -s mode the TransitionData autoload does not exist.
$GODOT --headless --path . -s path/to/script.gd
```

When run on its own, `mission_phase.tscn` uses its `test_cargo` export as the cargo.

## Engine gotchas

- **New `class_name`s and new `.tres` UIDs** only resolve after an editor filesystem scan. Until then, headless runs fail with "Unrecognized UID". Focus the open editor to trigger a scan: `osascript -e 'tell application "Godot" to activate'`.
- **Editor re-saves in-memory resources.** It can re-save resources it still holds in memory, which can bring back a deleted card `.tres`. The yard registry then re-registers it. After deleting cards, check `data/augments/` and `augments.tres` again.
- **CSV files in `res://`** get imported as translation tables. This creates junk `*.translation` files. Card CSVs need a `.csv.import` containing `[remap]` and `importer="keep"` (or `"skip"`).
- **Editor crashes.** The editor has crashed (SIGABRT) while hot-reloading scripts or scenes that were rewritten on disk. Relaunch it with the command above.

## Architecture

### Scene flow

`select_scenario` → `plan_phase` → `launch_report` → `launch_sequence` → `mission_phase`. A failed launch goes back to `plan_phase`.

Data passes between scenes through the **`TransitionData`** autoload (`scenes/singletons/transition_data.gd`), which holds:
- the scenario settings
- `selected_augments`
- the final cargo slot counts

### Cards

Cards are **`Augment`** resources (`classes/augment.gd`).
- **Card data:** each card is a `.tres` in `data/augments/`.
- **Registry:** cards are registered in the yard `Registry` `data/augments/augments.tres` (addon in `addons/yard`). Code loads cards through it with `get_all_string_ids()` and `load_entry(id)`.
- **Source text:** the designers' text lives in CSVs at the project root (columns Domain, Rarity, Card Name, …). The gameplay numbers are set by hand in each `.tres`. The CSV text is shown as-is (`gives_text`, `lore`…), while the card face is generated from the data (`summary_entries()`).
- **Picked card:** a picked card becomes an `AugmentInstance`, which holds random amounts rolled once (e.g. `"20-60"`) and the slots it takes.
- **Field types:**
  - `upgrades` apply once, at launch.
  - `daily` applies every night.
  - `risks` are `CardRisk` sub-resources, checked in the morning or at night.
  - `flags` are global effects (see `Augment.FLAG_TEXT`).
  - `synergy_*` adds bonuses from related cards. Some only count cards **adjacent in cargo order**, so the order of picks matters.
- **Launch-only domains** (Propulsion, Fuel, Logistics) never act as ship modules.
  - Logistics cards with a `plan_action` are used up when picked. They edit the deck in `plan_phase.gd`: remove, swap, crate, duplicate, trade-up, gambles, bonus slots.

### Launch

`classes/launch_profile.gd` turns the cargo into launch odds:
- **Thrust:** engines must beat the weight, at 10 thrust per ton.
- **Fuel:** the tanks must cover what the engines burn.
- **Reliability.**

The odds are the product of smoothstepped factors. The planning screen's odds bar, the launch report and the animated launch all read from this one class.

### Mission

The mission is split into simulation and view:
- **`classes/mission_state.gd` is the pure simulation, with no nodes.**
  - It owns resources, crew (`CrewMember`), ship modules (`ShipModule`, which wraps cards in cargo order), stations, the event deck, hazards and the night resolution.
  - It reports narration through a live feed (`drain_log()`).
  - All balance constants sit at the top of the file.
- **`scenes/mission_phase/mission_phase.gd` is the real-time view.** It runs the 08:00–20:00 clock and calls into the simulation:
  - `state.work()` every hour for each crew member
  - the alert API (`draw_event`, `begin_event_choice`/`finish_event_choice`, `ignore_event`, redraw/cancel)
  - `end_day()` at night
- **Helpers:**
  - `ship_view.gd`: ship cutaway, room rectangles in native 820×340 coordinates, walking paths.
  - `crew_sprite.gd`: astronauts.
  - `event_bubble.gd`: alert bubbles.
- **Terminal:** everything is narrated in a `TerminalLabel` (`classes/terminal_label.gd`), a typewriter queue. `then(callback)` runs code when the text reaches that point, so crew move only after their reply prints.

### Events

`MissionEvent` resources live in `data/events/`, each with `EventChoice` sub-resources.
- **Last choice:** the passive fallback, used when nobody answers in time.
- `skill`: which crew job is best at handling it.
- `location`: a station id or a `ShipView.ROOMS` key.
- `tags`: `hazard` (Navigation cards make these rarer), `isolation` (softened by some Communication cards), `good` (can't be cancelled).
- The event pool loads every `.tres` in the folder automatically.
