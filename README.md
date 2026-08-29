# Cleansive 1.5.61

Cleansive is a standalone one-click cleansing addon for **World of Warcraft Retail 12.1** (`120100`). It provides a compact Decursive-style workflow with a dark, class-colored interface inspired by the clarity of Ellesmere UI. The interface follows the language of your WoW client, English or French; either can be picked from the General page at any time.

## Installation

1. Exit World of Warcraft completely.
2. **Replace** the `Cleansive` folder in `_retail_/Interface/AddOns/`. Use the
   file named `Cleansive-<version>.zip`; GitHub's automatic "Source code"
   archive is not a working addon. Delete the
   old folder first rather than merging: a merge leaves behind files a newer
   version no longer loads, and they can still be read.
3. Enable Cleansive, log in, and type `/cleansive`.

Your settings live in `_retail_/WTF/Account/<account>/SavedVariables/Cleansive.lua`
and survive an update. They are written when you log out or reload, so a client
crash can lose the changes you made since the last one.

Cleansive can run alongside Decursive. Its own commands are `/cleansive` and `/cls`; the familiar `/dcr` and `/decursive` aliases are enabled only when Decursive itself is disabled.

You can also open Cleansive from **Options > AddOns**, the addon compartment, or **Options > Keybindings > AddOns**.

## Controls

- Left click: first cleansing or control spell.
- Right click: second spell.
- Ctrl + left click: third spell.
- Middle click: target the unit.
- Ctrl + middle click: set the unit as focus.
- Mouse button 4: third spell, the same action as Ctrl + left click.
- Mouse button 5: set the unit as focus, the same action as Ctrl + middle click.
- Drag the small `C` handle to move the grid.
- `/cleansive macro` creates a global mouseover macro. On that macro, no modifier uses the left-click spell, Shift uses the right-click spell, and Ctrl uses the Ctrl-click spell.

Red, blue, and orange identify the click to use. The optional L/R/C corner letters provide a color-independent cue. The thin bottom line identifies the affliction type.

## Features

- Automatic detection of class, specialization, talent, and pet cleansing spells.
- Blizzard-managed protected aura indicators for Retail 12.1 combat.
- Secure click casting for solo play, parties, and raids.
- Magic, Curse, Poison, Disease, Bleed, and Charm support.
- Player, class, and raid-group priorities and exclusions.
- A default raid order relative to your own group rather than an absolute
  1-to-8 order, so cleansing work spreads across dispellers on its own. Role
  and class orders are available instead; the priority list is read before any
  of them.
- Permanent and combat-only aura filters.
- A preview that pads the grid to any size from 1 to 40 with inert cells, so a
  raid layout can be sized and placed without a raid. A preview cell carries no
  secure unit, is never handed to the protected aura engine, and never enters
  the native sound registry. It closes itself when combat starts.
- Class-colored interface, test mode, dual timers (numeric cleanse cooldown plus a clockwise affliction-duration fade), stacks, tooltips, color-independent click hints, sound-channel selection, and sound diagnostics.
- Wrapping grid, horizontal-fill and vertical-fill cell arrangements with independent growth direction.
- English and French localization.
- A guided first-time setup, preselecting the language of your WoW client.
- Separate settings profiles for every character and specialization, copyable
  from one specialization to another.
- Profile export and import as plain text, from **Help > Share this profile**.
  The string is read by a key/value parser, never executed, and unknown or
  out-of-range values are refused and named rather than silently clamped. What
  travels is the look and the behavior; what never travels is your screen
  position, your language, and your priority and exclusion lists -- they name
  people.
- Optional grouping for dispel types you can only clear with an area or
  self-only ability: one indicator with a count instead of one cell per
  member. Off by default; the per-unit protected indicator stays in place
  either way, because it is the only signal for an aura the addon may not
  read.
- Where the grid appears is three combinable rules -- alone, in a party, in a
  raid -- on top of the combat-only rule. All of it runs through Blizzard's
  secure visibility driver, so it keeps working during combat.
- An afflicted-only visual mode.
- A persistent, clickable history of readable afflictions.
- A secure hover-cleanse key for the first configured cleansing spell.

## Commands

- `/cleansive` or `/cls`: open settings.
- `/cleansive show`: show the grid without changing the saved enabled setting.
- `/cleansive hide`: hide the grid for the current session without disabling Cleansive.
- `/cleansive enable`, `/cleansive disable`: persistently enable or disable Cleansive.
- `/cleansive reset`: reset frame positions.
- `/cleansive size <12-40>`, `/cleansive spacing <0-12>`: set an exact value.
- `/cleansive test`: toggle the preview.
- `/cleansive test <1-40>`: pad the preview to that many cells.
- `/cleansive test mixed|all|healthy`: choose how many preview cells light up.
- `/cleansive macro`: create or update the mouseover macro.
- `/cleansive prio`, `/cleansive skip`, `/cleansive filters`: open management tools.
- `/cleansive pradd`: add the current player target to the priority list.
- `/cleansive skadd`: add the current player target to the skip list.
- `/cleansive soundtest`: play the configured alert.
- `/cleansive soundstatus`: show native sound-registration and performance diagnostics.
- `/cleansive soundstatus <spell ID>`: say why one affliction is or is not announced.
- `/cleansive spells`: list the cleansing spells Cleansive detected, with their click and the types they cover.
- `/cleansive order`: print the current cell order and why each cell sits there.
- `/cleansive version`: print the version, client language, and class.
- `/cleansive prio clear`, `/cleansive skip clear`: empty a list without opening it.
- `/cleansive diag`: report this session's diagnostics; `diag copy` opens a selected, copyable support report and `diag reset` clears the stored counters.
- `/cleansive cdstatus`: show the last inspected cleansing-spell cooldown and display result.
- `/cleansive history`: open the clickable affliction history.
- `/cleansive control`: list the loss-of-control effects seen so far; `control <type>` starts or stops watching one; `control clear` empties the observed list without touching your choices.
- `/cleansive setup`: reopen the setup assistant.

When Decursive is disabled, `/dcr` and `/decursive` remain available as compatibility aliases.

## Roots, stuns and other loss of control

`C_LossOfControl` reports these per unit, so an effect on a group member is
readable -- but the data can be secret under restriction, and a secret count
must never be used as a loop bound. Cleansive reads defensively and treats a
refusal as "unknown", never as "no effect".

Nothing is watched by default. `/cleansive control` lists only what Cleansive
has actually observed, with the place it was seen; you pick which types deserve
a mark. **A type missing from that list is not proof it does not exist** -- it
means Cleansive has not seen it yet.

A watched effect marks the cell border. It never covers an affliction: a cell
with something to cleanse keeps its cleansing color, because cleansing is the
job.

## Retail 12.1 protected-aura behavior

During restricted combat, Blizzard can hide aura details from addon Lua. Cleansive delegates the visible affliction state, duration, stack count, and secure unit relationship to Blizzard's protected AuraContainer system. It never attempts to choose or cast a spell without a hardware click.

Native sound alerts are registered for known current-season afflictions. A separate event-based fallback covers readable auras and Charm when no native registration exists. If Blizzard protects an unknown spell ID during combat, no addon can safely identify that spell for native sound registration; the visual protected indicator and secure click remain available.

Spell-ID filters suppress matching native sound alerts and readable Lua fallback results. Blizzard intentionally prevents exact spell-ID filtering of some protected harmful auras on friendly units, so its protected visual indicator can remain visible even when that spell is ignored.

### Which tooltip you get, and why

Lua cannot read whether a protected AuraSlot is currently visible. Rather than
guess, Cleansive hands hover over to Blizzard's own frame: a painted AuraSlot
owns mouse motion and shows the protected aura tooltip, while clicks pass
through to Cleansive's secure unit button underneath.

The consequence is worth knowing. On a cell the engine has painted, you get
Blizzard's aura tooltip -- the affliction itself -- and *not* Cleansive's click
map or its reminder of which ability you must cast manually. Those lines appear
on resting cells when their visuals are enabled. This is a deliberate trade:
the engine is the only party that knows whether an indicator is on screen.

"Only show afflicted cells" is therefore a visual mode, not a way to remove
secure hitboxes. Resting cells become invisible, but their fixed click positions
remain active so a protected AuraSlot can pass cleansing clicks through during
combat. Avoid clicking empty grid positions while this mode is enabled.

The hover-cleanse key also respects these restrictions: it casts through a secure action button on your mouseover, target, or player. It never asks Lua to select an afflicted unit during combat, because the secure engine evaluates targeting conditions only and cannot read auras.

## Known limitations

- An affliction whose spell ID Blizzard protects during combat cannot be
  identified by any addon, so it can show its protected indicator without ever
  making a sound.
- A stack increase is not a new application. The native alert fires when an
  affliction appears; going from two stacks to three is silent by design. The
  same affliction can sound again once it has fully expired and returns.
- Cleansive cannot recolor what the protected aura engine paints. The colors it
  owns are Blizzard's.
- The season spell list is calibrated by hand. A new season goes quiet on its
  unlisted afflictions until the list is updated.

## Reporting a problem

Run `/cleansive diag copy`, copy the block, and paste it into your report. It
carries the version, the active Retail 12.1 restrictions, the aura-engine state,
the sound registry, deferred work and refusals -- and no character name. Add
what you were doing, and whether it was a dungeon, a raid, or PvP.

If one affliction never makes a sound, `/cleansive soundstatus <spell ID>` names
the reason on its own.

## Recent changes

- **1.5.61** - the protected aura engine is no longer rebuilt during a boss fight, and the General page opens with the profile and the engine's condition.
- **1.5.60** - dragging a size slider no longer relays the whole grid at every notch, and a switch that cannot apply now says why.
- **1.5.59** - the tooltip stops promising a mouse button that does nothing, and the addon credits what it learned from.
- **1.5.58** - Cleansive can watch roots, stuns and other loss-of-control effects on your group, but only the ones you picked from what it has actually seen.
- **1.5.57** - the sound registry states its condition in a sentence, the affliction fade can be switched off on its own, and sizes can be set by command.
- **1.5.56** - the cell order can follow role or class instead of raid group, and the release archive is checked before it ships.
- **1.5.55** - three combinable rules for where the grid appears (alone, party, raid), and the grid stays visible while you are configuring it.
- **1.5.54** - a search box in the settings window finds a setting and says which page it is on.
- **1.5.53** - the tooltip says why a cell sits where it does, and the affliction history remembers where each one was seen.
- **1.5.52** - four starting points for the look, a reset that touches only the page you are on, and two clicks before anything is destroyed.
- **1.5.51** - the settings window says its real state, hides what does not apply, and every window comes back where you left it.
- **1.5.50** - a profile can be exported as text and imported after a preview of what would change. It carries no character name, no screen position, and no player list.
- **1.5.49** - a Help page inside the addon: every command, what to do when something looks wrong, and what Cleansive cannot do.
- **1.5.48** - Cleansive can now say what it detected: the spells it found, why one affliction stays silent, and the order the cells are in.
- **1.5.47** - the preview pads the grid to any size from 1 to 40, so a raid layout can be tuned without a raid. Preview cells are inert.
- **1.5.46** - a sound alert is replaced without a silent gap: the new registration is created first, and a refused replacement keeps the working one. `/cleansive diag copy` opens a selected, copyable support report.
- **1.5.45** - a styling pass asks the client for permission before its nine calls instead of after.
- **1.5.44** - mouse button 4 reports its own cooldown.
- **1.5.43** - mouse buttons 4 and 5 mirror the two awkward modifier combinations.
- **1.5.42** - the six 12.1 restriction types are recorded, and the client's own refusals are logged by name.

The full history, with the reasoning behind each change, is in [CHANGELOG.md](CHANGELOG.md).

## Français

Cleansive est un addon autonome de dissipation en un clic pour WoW Retail 12.1. Lors d’une nouvelle installation, l’interface suit automatiquement la langue du client WoW : français ou anglais. Vous pouvez en changer depuis la page **Général** de `/cleansive`, puis taper `/reload` pour actualiser les libellés déjà créés.

Cleansive peut rester actif en même temps que Decursive : utilisez `/cleansive` ou `/cls`. Les alias `/dcr` et `/decursive` ne sont ajoutés que si Decursive est désactivé.

Les restrictions d’auras de WoW 12.1 peuvent masquer le nom exact d’un effet en combat. Dans ce cas, l’indicateur visuel et le clic sécurisé restent gérés par Blizzard. L’alerte sonore native couvre les afflictions connues ; une aura inconnue dont l’identifiant est protégé peut rester silencieuse.

## Credits

Cleansive owes its shape to Decursive, which defined this kind of addon. It was
measured against Salve, Zhaou's Decursive, Simple Decursive, ClickCleanse,
K Decurse and LFDecurse: their behaviour taught it a great deal and was written
again from Blizzard's own API. None of their code is in here, and the licenses
would not have allowed it.

## License

Cleansive is distributed under the MIT License.

Copyright © 2026 Ro. See `LICENSE.txt` for the full license text.
