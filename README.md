# Cleansive 1.5.24

Cleansive is a standalone one-click cleansing addon for **World of Warcraft Retail 12.1** (`120100`). It provides a compact Decursive-style workflow with a dark, class-colored interface inspired by the clarity of Ellesmere UI. The interface follows the language of your WoW client, English or French; either can be picked from the General page at any time.

## Installation

1. Exit World of Warcraft completely.
2. Copy the `Cleansive` folder into `_retail_/Interface/AddOns/`.
3. Enable Cleansive, log in, and type `/cleansive`.

Cleansive can run alongside Decursive. Its own commands are `/cleansive` and `/cls`; the familiar `/dcr` and `/decursive` aliases are enabled only when Decursive itself is disabled.

You can also open Cleansive from **Options > AddOns**, the addon compartment, or **Options > Keybindings > AddOns**.

## Controls

- Left click: first cleansing or control spell.
- Right click: second spell.
- Ctrl + left click: third spell.
- Middle click: target the unit.
- Ctrl + middle click: set the unit as focus.
- Drag the small `C` handle to move the grid.
- `/cleansive macro` creates a global mouseover macro. On that macro, no modifier uses the left-click spell, Shift uses the right-click spell, and Ctrl uses the Ctrl-click spell.

Red, blue, and orange identify the click to use. The optional L/R/C corner letters provide a color-independent cue. The thin bottom line identifies the affliction type.

## Features

- Automatic detection of class, specialization, talent, and pet cleansing spells.
- Blizzard-managed protected aura indicators for Retail 12.1 combat.
- Secure click casting for solo play, parties, and raids.
- Magic, Curse, Poison, Disease, Bleed, and Charm support.
- Player, class, and raid-group priorities and exclusions.
- Permanent and combat-only aura filters.
- Class-colored interface, test mode, dual timers (numeric cleanse cooldown plus a clockwise affliction-duration fade), stacks, tooltips, color-independent click hints, sound-channel selection, and sound diagnostics.
- Wrapping grid, horizontal-fill and vertical-fill cell arrangements with independent growth direction.
- English and French localization.
- A guided first-time setup, preselecting the language of your WoW client.
- Separate settings profiles for every character and specialization.
- Optional grouping for dispel types you can only clear with an area or
  self-only ability: one indicator with a count instead of one cell per
  member. Off by default; the per-unit protected indicator stays in place
  either way, because it is the only signal for an aura the addon may not
  read.
- Secure combat-only auto visibility and an afflicted-only visual mode.
- A persistent, clickable history of readable afflictions.
- A secure hover-cleanse key for the first configured cleansing spell.

## Commands

- `/cleansive` or `/cls`: open settings.
- `/cleansive show`: show the grid without changing the saved enabled setting.
- `/cleansive hide`: hide the grid for the current session without disabling Cleansive.
- `/cleansive enable`, `/cleansive disable`: persistently enable or disable Cleansive.
- `/cleansive reset`: reset frame positions.
- `/cleansive test`: toggle test mode.
- `/cleansive macro`: create or update the mouseover macro.
- `/cleansive prio`, `/cleansive skip`, `/cleansive filters`: open management tools.
- `/cleansive pradd`: add the current player target to the priority list.
- `/cleansive skadd`: add the current player target to the skip list.
- `/cleansive soundtest`: play the configured alert.
- `/cleansive soundstatus`: show native sound-registration and performance diagnostics.
- `/cleansive cdstatus`: show the last inspected cleansing-spell cooldown and display result.
- `/cleansive history`: open the clickable affliction history.
- `/cleansive setup`: reopen the setup assistant.

When Decursive is disabled, `/dcr` and `/decursive` remain available as compatibility aliases.

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

## 1.5.24 changes

- A retired dispel type actually stays inert. 1.5.23 replaced its filters with an empty table, and `ConfigureButtonAuraContainer` handed the real ones straight back -- it walks every accumulated slot key and runs on every layout, roster assignment and filter edit, so the claim in the 1.5.23 notes did not hold in the final state. The active set is remembered now and consulted wherever slot filters are applied.
- A failed slot reconfiguration is diagnosed and retried instead of being permanent. The wanted set was stored before the cells were reconciled, so a cell that failed was left on the Lua fallback and the next call returned early without retrying it -- until a reload. Failures are recorded, reported once, and retried up to three times; the retry is owed when containers exist but are not all covered, because a filter that fails for one slot fails it on all 82.
- Tests: 452 to 465. The mock recorded nothing for `SetAuraSlotCandidateFilters` and could not fail it, which is the root of both defects above: the generic stub answered success and the suite could not see either one. It now stores the filters and can be made to fail.
- README: the layout modes no longer promise a single row or column, and the hover-cleanse key is described as what it is -- it casts the first configured spell on mouseover, target, then player. It never picks an afflicted unit.
## Français

Cleansive est un addon autonome de dissipation en un clic pour WoW Retail 12.1. Lors d’une nouvelle installation, l’interface suit automatiquement la langue du client WoW : français ou anglais. Vous pouvez en changer depuis la page **Général** de `/cleansive`, puis taper `/reload` pour actualiser les libellés déjà créés.

Cleansive peut rester actif en même temps que Decursive : utilisez `/cleansive` ou `/cls`. Les alias `/dcr` et `/decursive` ne sont ajoutés que si Decursive est désactivé.

Les restrictions d’auras de WoW 12.1 peuvent masquer le nom exact d’un effet en combat. Dans ce cas, l’indicateur visuel et le clic sécurisé restent gérés par Blizzard. L’alerte sonore native couvre les afflictions connues ; une aura inconnue dont l’identifiant est protégé peut rester silencieuse.

## License

Cleansive is distributed under the MIT License.

Copyright © 2026 Ro. See `LICENSE.txt` for the full license text.
