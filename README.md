# Cleansive 1.5.43

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
  1-to-8 order, so cleansing work spreads across dispellers on its own.
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
- `/cleansive diag`: report this session's diagnostics; `diag reset` clears them.
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

## Recent changes

- **1.5.43** - mouse buttons 4 and 5 mirror the two awkward modifier combinations.
- **1.5.42** - the six 12.1 restriction types are recorded, and the client's own refusals are logged by name.
- **1.5.41** - nothing visible is left behind when the client refuses a styling pass.
- **1.5.40** - one refused call no longer takes the whole styling pass with it.
- **1.5.39** - a failed sound registration is retried; the two status plates stack instead of overlapping.

The full history, with the reasoning behind each change, is in [CHANGELOG.md](CHANGELOG.md).
## 1.5.34 changes

- The pending plate no longer appears for deferrals the game raised on its own. It announces only a change you asked for.

## 1.5.33 changes

- One affliction missing from the seasonal sound list was found in a recorded session and added.

## 1.5.32 changes

- In a raid, the cell order starts at your own group and wraps, so two dispellers no longer reach for the same cell first. The priority list still comes before it.

## 1.5.31 changes

- Auras that punish the dispeller carry a warning ring and a `!`. The click stays available; it just cannot be made by reflex any more.

## 1.5.30 changes

- The priority chevrons point in the direction they actually move things.
- The live preview scales its whole content with the cell, so a 40 px cell no longer overlaps its own labels.

## 1.5.29 changes

- Every slider shows its value; opacity reads as a percentage.
- Clearer labels for the cleanse cooldown and the sound alert limit.
- A real empty state for the history, and pagination only when there is more than one page.
- Drawn priority arrows with visible disabled states.

## 1.5.28 changes

- A change deferred by combat now shows a plate next to the grid until it is applied.
- A specialization with no cleansing spell says so instead of showing cells that can never light up.

## 1.5.27 changes

- A pass that fails on both a retired and an active dispel type now names the active one in the engine message.

## 1.5.26 changes

- A superseded aura-engine retry timer can no longer release the guard held by a newer one.
- A character left with no dispel type still retries the neutralisation of its retired slots.
- Cleanup failures get their own diagnostic line instead of reporting an incomplete engine at full slot count.

## 1.5.25 changes

- Retries are scheduled, not merely allowed. 1.5.24 set a flag and waited for some other spell event to call the reconciliation again, so a single transient failure could leave cells on the Lua fallback for the rest of the session. A bounded timer now drives them, guarded by a generation so a change of type set cancels the pending one, and deferring to `PLAYER_REGEN_ENABLED` if it fires during combat.
- A failed neutralisation counts. Readiness only looked at the wanted types, so a retired type left analysing auras raised no retry at all. The pass now reports two outcomes: whether the cell can use the engine, and whether the pass was complete.
- The retry budget starts again for each new type set, and the warning prints once per generation rather than once per attempt -- four identical lines in the chat frame, where the 1.5.24 notes promised one. The slot counter adds every configured slot instead of only whole ready cells, which could report `0/246` while 164 slots were live.
- Tests: 465 to 470. Writing the autonomous-recovery test immediately found a fifth defect of my own: the single-timer guard blocked rescheduling when the generation changed, so the stale timer no-opped and no new one was ever armed.
## Français

Cleansive est un addon autonome de dissipation en un clic pour WoW Retail 12.1. Lors d’une nouvelle installation, l’interface suit automatiquement la langue du client WoW : français ou anglais. Vous pouvez en changer depuis la page **Général** de `/cleansive`, puis taper `/reload` pour actualiser les libellés déjà créés.

Cleansive peut rester actif en même temps que Decursive : utilisez `/cleansive` ou `/cls`. Les alias `/dcr` et `/decursive` ne sont ajoutés que si Decursive est désactivé.

Les restrictions d’auras de WoW 12.1 peuvent masquer le nom exact d’un effet en combat. Dans ce cas, l’indicateur visuel et le clic sécurisé restent gérés par Blizzard. L’alerte sonore native couvre les afflictions connues ; une aura inconnue dont l’identifiant est protégé peut rester silencieuse.

## License

Cleansive is distributed under the MIT License.

Copyright © 2026 Ro. See `LICENSE.txt` for the full license text.
