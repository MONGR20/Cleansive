# Cleansive 1.6.35

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

The three cleanse clicks are yours to place. **Set up the clicks**, on the
Dispels page, opens a window where each row listens for the combination you
press. `/cleansive clicks 3 SHIFT-2` does the same from the chat box.

By default:

- Left click: first cleansing or control spell.
- Right click: second spell.
- Ctrl + left click: third spell.
- Mouse button 4: third spell, as long as you have not claimed button 4 yourself.

Two combinations stay with Cleansive and cannot be taken:

- Middle click: target the unit.
- Ctrl + middle click: set the unit as focus.
- Mouse button 5 mirrors the focus click, unless you have claimed button 5.

Also:

- Drag the small `C` handle to move the grid.
- `/cleansive macro` creates a global mouseover macro. On that macro, no modifier uses the first cleanse, Shift the second, and Ctrl the third.

Red, blue, and orange identify the click to use. The optional corner letters
provide a color-independent cue and follow the combination you set: a plain
button gives one letter, a modified one gives the modifier's initial in front
of it. The thin bottom line identifies the affliction type.

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
- `/cleansive alerts`: why the last sound alerts fired or stayed quiet; `alerts clear` empties the log.
- `/cleansive coverage`: what the season list covers, type by type.
- `/cleansive order`: print the current cell order and why each cell sits there.
- `/cleansive version`: print the version, client language, and class.
- `/cleansive prio clear`, `/cleansive skip clear`: empty a list without opening it.
- `/cleansive diag`: report this session's diagnostics; `diag copy` opens a selected, copyable support report and `diag reset` clears the stored counters.
- `/cleansive cdstatus`: show the last inspected cleansing-spell cooldown and display result.
- `/cleansive history`: open the clickable affliction history.
- `/cleansive control`: list the loss-of-control effects seen so far; `control <type>` starts or stops watching one; `control clear` empties the observed list without touching your choices.
- `/cleansive setup`: reopen the setup assistant.
- `/cleansive profile`: list the named profiles and the active one. `new <name>` creates one from your current settings, `use <name>` points this specialization at it, `own` returns to this specialization's own profile, `rename <old> | <new>`, `delete <name>`. Changing profile is refused while you are fighting: a profile switch cannot be half applied.
- `/cleansive clicks`: print the three cleanse clicks. `clicks <1-3> <combination>` moves one, as in `clicks 3 SHIFT-2`: a mouse button from 1 to 5, with any of ALT, CTRL and SHIFT in front. A combination already taken by another cleanse, or reserved for targeting and focus, is refused whole. Remapping is refused while you are fighting, for the same reason a profile switch is.
- `/cleansive profile env <place> <profile>`: load a named profile in one place only -- `world`, `dungeon`, `raid` or `pvp`. Leave the profile out to remove the override. `/cleansive profile lock` freezes places, so the profile no longer changes when you zone. Both are also in the profile manager window.
- `/cleansive sound`: list the alert sounds this client actually knows, and pick one by name. Blizzard's own alert registry takes a sound file, so afflictions the client protects keep the shipped sound.

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

- **1.6.35** - the report now says how many refused regions got a second chance and how many took it. Writing that counter surfaced a real defect: a successful retry never cleared its mark, so yesterday's key could leave a region dark through tomorrow's, silently.
- **1.6.34** - a mythic key holds ChallengeMode from start to finish, so every combat exit was replaying every refused region for nothing: 7 602 refusals, about sixty rounds of them. A refusal now remembers which restrictions were active, and only their release earns a retry.
- **1.6.33** - a test claimed the restriction event never works during its own dispatch, but only checked that a timer existed. It now counts the calls: zero during the event, one after. No shipped code changed.
- **1.6.32** - the restriction API answers false while its own change event is being dispatched, so classifying a refusal from inside that handler would call it permanent. The deferral that protects us is now pinned by a test.
- **1.6.31** - a mythic key keeps ChallengeMode active throughout, so "no combat lockdown" never meant "no restriction": 5 571 refusals were being condemned as permanent when a restriction could still lift. Every restriction now counts, and every path goes through the same rule.
- **1.6.30** - one refusal memory for every region the engine lends us, instead of one flag per defect found. A refusal under combat lockdown is replayed; a refusal outside it is remembered, because combat was not the cause.
- **1.6.29** - the refusal memory was stored ON the forbidden region, so it was refused too and the flag never held: 846 repeats in one session. It lives on our own table now. The cause 1.6.28 announced was wrong, and this entry says why.
- **1.6.28** - the click hint stopped reading its text back from the engine's own region. The reason given at the time — that the returned value was what the client refused — was wrong, and 1.6.29 says why.
- **1.6.27** - external audit fixes: an import could write a profile you were no longer looking at, a region the client refuses is now abandoned whole rather than retried every pass, an absorbed refusal is counted instead of vanishing, and the cooldown diagnostic no longer invents an error on success.
- **1.6.26** - `SetText` was the one unguarded protected call in the click hint, and the client refused it in game: it took its caller down with it, up to and including the whole button layout.
- **1.6.25** - interface review fixes: a click hint that cannot fit now falls back to the cleanse number instead of vanishing, section titles reach 4.5:1, a truncated profile name is readable in its tooltip, and seven controls added since 1.6.20 finally explain themselves.
- **1.6.24** - external audit fixes: a long click combination no longer overflows its cell, a thirty-two byte profile name no longer overflows its place button, the drag handle and the click window wake up when combat starts, and every profile is reachable from the window instead of the seventh onward being sent to the chat box.
- **1.6.23** - the profile window answered nothing on an empty database: the name field's background was darker than the panel, so the one control that could unlock everything was the one you could not see.
- **1.6.22** - the drag handle follows the grid it moves: it stayed on screen alone when the cells were hidden by a group, raid or combat rule.
- **1.6.21** - the 690 refusals had not dropped, they had moved to the next call: a value that has not changed is no longer re-applied to an engine-owned object.
- **1.6.20** - what combat refuses, it refuses whole: remapping a click, applying an import and locking places all wrote before discovering combat forbade the rest. Every surface now names the gesture that is actually bound.
- **1.6.19** - after a remapped click the cell could show the wrong cooldown: the internal ledger still read the old hardcoded gestures.
- **1.6.18** - cleanse clicks can be remapped to any mouse button with any modifiers, and nothing is written while a conflict exists.
- **1.6.17** - per-place profile overrides: open world, dungeon, raid, PvP. They carry no settings of their own, only the name of a profile you already made.
- **1.6.16** - the engine's frame level is only re-applied when it actually changes, which is what turned one refusal into 690 over a single key.
- **1.6.15** - external audit fixes: the vertical-bar profile migration never ran for the people who needed it, and the mouse wheel was skipping half a page.
- **1.6.14** - a real Mythic+ log at last: the native sound registry holds under restriction, but the engine's frame level is refused 690 times a key. That refusal is now remembered instead of retried.
- **1.6.13** - the settings pages actually scroll: replacing the scroll template's own handlers left its bar unconfigured, so nothing moved.
- **1.6.12** - two fixes the 1.6.11 changelog claimed but did not contain, plus the migration of old profile names containing a vertical bar.
- **1.6.11** - external audit fixes: profile changes are refused mid-combat, a shared profile is really loaded at login, and the unprotected layer follows the same visibility rules as the grid.
- **1.6.10** - the alert sound button is verified end to end: unwiring it now fails a test.
- **1.6.9** - named profiles, shareable across characters and specializations. A specialization's own profile is never destroyed, so coming back to it always works.
- **1.6.8** - raids can have their own cell size and spacing, off by default. Eighteen places read the geometry directly; they now all go through one accessor.
- **1.6.7** - the settings pages scroll. Each page declares its height, and a check refuses any control that runs past it. The Help page loses its own nested scroll.
- **1.6.6** - the alert sound can be picked from the game's own sounds with `/cleansive sound`; ids are read from SOUNDKIT at call time, never copied in.
- **1.6.5** - optional class color on resting cells, so you can tell who is who without reading a name. An afflicted cell always keeps its dispel color.
- **1.6.4** - the addon no longer plays alerts for cells it has decided not to show: turning off a visibility context now removes the native sound registrations the client was playing on its own. The overlap check descends into controls and covers the sidebar.
- **1.6.3** - nine overlapping controls fixed in the settings window, and the overlap detector that should have caught them: it silently skipped every wrapped explanation line, understood two anchor points out of nine, and never looked at the window footer.
- **1.6.2** - three interface finishes: a TEST plate beside the grid while the preview is open, a Help page that says it continues below, and windows that rescale when the screen changes.
- **1.6.1** - fixes from an external audit and from in-game screenshots: overlapping labels on three pages, the preview refusing to open mid-combat, and a profile repair that had fallen eight settings behind.
- **1.6** - the version that closed the competitor review: a real preview, profile sharing, a Help page, loss-of-control watching, and a release pipeline that verifies before it publishes.
- **1.5.67** - the settings preview stops promising a click letter and a cooldown number the real grid will not draw.
- **1.5.66** - the observed loss-of-control catalogue can be copied out, and a locked-down invariant now guards what a shared profile may carry.
- **1.5.65** - the test harness now lives in the repository, and the release pipeline verifies before it publishes.
- **1.5.64** - the report now carries what startup cost, which engine drives which cell, and the exact build it came from.
- **1.5.63** - Cleansive records why each alert did or did not fire, which ability judged range, and what the season list covers type by type.
- **1.5.62** - every protected call now reads its own result, and the preview belongs to whoever opened it.
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
