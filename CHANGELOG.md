# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par des tests de non-régression dans `j/tests` (`npm test`). Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

## 1.5.6

- Grouped dispel types keep their protected engine cell. 1.5.4 removed it, which is what made grouping unsafe: an aura the addon may not read had no cell, no indicator and no sound. The cell is now drawn as a thin type stripe instead of a filled block, so the wall of cells is gone without the signal going with it.
- The grouped indicator follows `UNIT_AURA` instead of waiting for a full refresh, coalescing bursts into one pass.
- The readable sound fallback finds grouped afflictions again. Selecting a cell's clickable spell still ignores them; the two searches are now separate.
- The engine's aura-type set is rebuilt when it changes, so a specialization or talent change no longer leaves a stale configuration. A change made during combat is applied once combat ends.
- The indicator is anchored opposite the growth direction, so it no longer sits on top of the first cell in the upward layouts, and it resizes with the cell-size slider.
- The indicator shows its count from 1, carries a colour-independent `!`, appears in test mode, counts only the player for a self-only ability, and follows the configured type order.
- Shortened the option label so it fits its control.

## 1.5.5

- "Group untargetable cleanses" is now opt-in. Enabled by default in 1.5.4, it removed the protected engine cell for the grouped types without providing an equally reliable replacement: when an aura is unreadable in restricted combat and the native sound does not cover the spell, nothing was shown at all. Profiles written by 1.5.4 are reset to opt-in once, so the fix reaches players who already ran it. A deliberate choice made afterwards is left alone.
- The option still does what it was asked to do. Turn it on and a Demon Hunter or a Shaman gets a single indicator instead of one cell per member; the remaining gaps on the protected path are being addressed for 1.5.6.

## 1.5.4

- Added "Group untargetable cleanses" (on by default). When the only way to clear a dispel type is an area or self-only ability, it is shown once next to the grid with a count of affected allies instead of on every unit cell. Reported by a Demon Hunter: Reverse Magic cannot be aimed at an ally, so forty cells all said the same thing. A Shaman gains the same for Poison Cleansing Totem; a class that can click every type sees no change.
- The grouped indicator counts afflictions Lua can read. In restricted combat it under-reports rather than guessing, and its tooltip says so; the native sound alert still fires there.

## 1.5.3

- Fixed charge-based cleanse cooldowns when Retail 12.1 protects the regular cooldown state. Cleansive now asks the documented active-charge duration API directly and prefers that more specific duration object whenever one exists.
- Fixed the numeric cleanse cooldown disappearing after the readable Lua fallback removed the dispelled aura. The secure click mapping now survives the delayed 750 ms cooldown probes and is cleared only after a readable ready state.
- Fixed `/cleansive macro` using a display/override spell name instead of the same stable base name used by secure cell clicks.
- Locking the grid now disables the hidden anchor's mouse input as well as hiding its artwork; changes made during combat are safely deferred.
- Late `/dcr` and `/decursive` compatibility aliases are queued for Blizzard's slash-command importer, while remaining disabled when Decursive is enabled.
- Clarified that "Only show afflicted cells" is visual: protected hitboxes must remain fixed and active for secure clicks. Also removed the last private French dispel-type table and documented `/cleansive cdstatus`.

## 1.5.2

- Fixed a Lua error that fired on every cooldown refresh in protected combat. `duration:IsZero()` returns a secret boolean there, and negating a secret raises; the result was 5546 identical errors in a single session, after which WoW disabled the addon. The value is now checked with `canaccessvalue` first, and an unreadable one means "unknown" rather than a guess -- the duration is still applied, only its state is left undetermined.

## 1.5.1

- Documented why a painted cell shows Blizzard's aura tooltip instead of Cleansive's, in the README, in the "Only show afflicted cells" and "Show tooltips" hints, and as a guard comment in the code. Lua cannot read AuraSlot visibility, so hover ownership is given to the engine on purpose; 1.4.5 and 1.4.6 each guessed from Lua and each got it wrong in one direction.

## 1.5.0

- The tooltip names the ability to cast manually on the protected path. Lua never learns which aura is on the unit there, so it cannot name the ability for *that* affliction; it now lists the dispel types that have no click at all, which is the honest substitute. The 1.4.4 note below overstated this: the naming only ever worked on the readable Lua fallback.
- Translated dispel-type names moved from two tables private to the options file into Locale.lua, behind `NS:GetTypeLabel`. They were unreachable from every other file, and outside the place the rest of the translations live.

## 1.4.9
- Fixed the numeric cleanse cooldown disappearing in real combat when WoW emitted an initial global-cooldown update before the actual spell cooldown was populated. Cleansive now keeps the secure click mapping through that short race and rechecks it at 0, 60, 200, and 750 ms.
- Charge-based cleansing spells now use Retail 12.1's documented `C_Spell.GetSpellChargeDuration` when their normal cooldown duration is zero.
- Moved the numeric cooldowns into a separate unprotected UIParent overlay that mirrors the protected grid. WoW can now update the numbers during combat without a protected parent blocking the visual change; explicit countdown visibility, font contrast, and a high frame strata keep them above AuraSlot visuals.
- Added `/cleansive cdstatus` to report the last inspected spell, cooldown source, active state, and whether the duration object reached the display layer.

## 1.4.8
- Removed the misleading primary-cleanse fallback that repeated one cooldown across healthy, hidden, unavailable, and differently mapped cells. With protected combat data, the numeric cooldown now appears only for the exact spell selected by the secure click; readable auras still select their exact mapping directly.
- Rebuilt the native sound plan around complete, priority-ordered units. Ordinary pets no longer consume a player's place when pet scanning is disabled, active vehicles use the displayed vehicle token, and self-only abilities register alerts for the player only.
- Vehicle and pet-token events now refresh native sound registrations immediately, including when the token appears during combat.
- In afflicted-only mode, transparent healthy cells no longer react to the mouse. A visible Blizzard AuraSlot owns its protected aura tooltip and highlight while all cleanse clicks pass through to Cleansive's secure unit button.
- Manual-only afflictions use a `!` badge, and the Dispels page names the ability that must be cast manually. Blizzard's protected tooltip remains dedicated to the actual affliction.
- Fixed the sound-budget slider overlapping Quick tools and enlarged the options window just enough to preserve comfortable spacing.
- Removed redundant full aura rebuilds after `SetUnit` and `RefreshAll`; Blizzard's container already refreshes on unit and candidate-filter changes.

## 1.4.7
- The dispel cooldown no longer waits for a Cleansive click on that cell. On the protected path Lua never learns which spell a cell needs, so the swipe stayed blank in combat until the cell had been clicked once. It now falls back to the primary dispel: nothing shows while the spell is ready, and every cell shows the swipe while it is not.
- Native sound registrations are bounded by a budget instead of merely warning past 4500. The roster is already in priority order, so the budget is spent on the units that matter most, and `/cleansive soundstatus` states how many were left out. Those units keep the readable Lua fallback. The ceiling is adjustable in General.
- The size preview reacts to the slider in all three layouts. Vertical was pinned at 20 px, so moving "Cell size" produced no visible change at all; each mode now has a cap high enough for the control to feel alive, and the vertical spacing follows the cell size.

## 1.4.6
- The aura container follows a passenger into a vehicle. 1.4.5 only moved the secure click target: the container stayed bound to the original unit token, so protected afflictions were painted for the wrong unit.
- Vehicle tokens get their own native sound registration; without one, no alert fired while a group member was in a vehicle.
- A dispel type covered only by an area or self-only ability now gets native sound registrations. 1.4.4 claimed the alert fired for these; it only did so on the readable Lua fallback, never on the protected path.
- Cleansive no longer forces a full aura rebuild on every UNIT_AURA. The container already processes those events incrementally, and re-syncing now happens only when the unit it is bound to actually changed.
- Afflicted-only mode no longer removes the highlight and tooltip from cells the engine has painted. Lua cannot see the aura on that path, so "no aura" was being read as "empty cell" on exactly the cells that mattered.

## 1.4.5
- Vehicles are handled. A passenger's afflictions are read from the pet slot that carries the vehicle, and the secure click follows them through an attribute driver, so the swap also works during combat when Lua cannot rewrite the attribute. `UNIT_ENTERED_VEHICLE` and `UNIT_EXITED_VEHICLE` refresh the affected cell, and aura events fired by a vehicle token are routed back to the cell that owns the passenger.
- `/cleansive soundstatus` states which season the spell list was calibrated for, and how many IDs it holds. When the season rotates the list silently stops matching and sounds go quiet; this makes that legible instead of looking like a broken addon.
- The sound delta no longer prints `-0 removed`.

## 1.4.4
- Area and self-only cleansing abilities no longer take a click cell, but the affliction types they cover are drawn again. 1.4.1 removed them from the click mapping to stop Psychic Scream from occupying the priest's left click, and that also removed the detection: a Demon Hunter lost every Magic indicator, and a Shaman every Poison indicator, because Reverse Magic and Poison Cleansing Totem are their only options for those types.
- Such cells are painted in a neutral grey with the affliction's type stripe, carry no click letter and no cooldown swipe, and their tooltip names the ability to cast manually (readable path only until 1.5.0).
- The sound alert now fires for these afflictions too.

## 1.4.3
- Profiles written before 1.4.2 still carried their own copy of the affliction history. Their entries are folded into the shared global history on load, then the per-profile copies are removed.

## 1.4.2
- Profiles are no longer resolved before the specialization is known, so no placeholder "0" profile is created or saved. Any leftover one is removed on login.
- The account-wide database migrated from earlier versions now seeds the first profile of every character, instead of only the first character to log in.
- The affliction history moved from the profiles to the global section: it is a knowledge base, not a preference, and no longer duplicated per specialization nor reset when switching spec.
- Settings belonging to features removed in 1.2.6 (`liveCount`, `scanInterval`, `showLiveList`, the live-list position) are pruned from migrated profiles.
- `RememberAura` short-circuits when the spell is already the most recent entry and compares spell IDs numerically, removing two string allocations per comparison on the UNIT_AURA path.
- Closing the setup assistant with Escape now counts as finishing it, so it no longer reopens on every login.
- The assistant reuses the option labels from Locale.lua, so it can no longer describe a toggle differently from the settings pages.
- The assistant announces the required reload when the language changes in either direction, not only when switching to French.
- `/cleansive ignore <id>` is listed in the command help.

## 1.4.1
- The grid can be moved again while "Show only in combat" is enabled. The visibility state driver now acts on a child container, so the drag handle and its context menus stay reachable out of combat.
- Afflicted-only mode no longer answers the mouse over hidden cells: the highlight and the tooltip are suppressed while a cell is painted at alpha 0.
- The cleanse key is no longer bound when the character knows no cleansing spell, so it can no longer take a game keybinding hostage for a button that casts nothing.
- Captured key combinations are assembled in WoW's canonical ALT-CTRL-SHIFT order, so combinations involving Alt now trigger.
- The generated cleanse macro uses the base spell name, matching the secure click bindings.
- Assigning the key during combat now reports that the binding is deferred instead of claiming it is active.
- Renamed "Priority cleanse key" to "Hover cleanse key" so the label matches what the secure macro can actually do.

## 1.4.0
- Added a one-page first-time setup assistant.
- Added automatic migration from the former flat database to character-and-specialization profiles.
- Added secure combat-only visibility through WoW's state-driver system.
- Added an afflicted-only mode that hides healthy visuals without moving or recreating protected click cells in combat.
- Added a persistent clickable history for readable afflictions; entries can be added to or removed from permanent filters.
- Added a per-profile priority-cleanse key backed by a secure action button.
- Aligned specialization and addon enable-state checks with the documented Retail 12.1 namespaces and signatures.
- Made permanent and combat-only spell filters suppress matching native sound registrations.
- Added faction-change refreshes for Charm and mind-control transitions.
- Made the Cell size preview update immediately and protected aura layers inherit the cell rectangle, so the slider also resizes their visible overlays while frame positioning is locked.
- Split the two timers clearly: the cleansing spell actually used on a cell shows its cooldown as a number, while a protected clockwise dark sweep progressively removes the cell color as the affliction expires.
- Refreshes cleanse cooldown numbers from Retail's cooldown and charge events while ignoring the global cooldown.
- Moved the numeric cleanse cooldown out of Blizzard's secret-aura descendants and onto a safe top cell layer, so it continues updating after a real secure click in combat.
- Suppressed the affliction countdown text completely; affliction time is communicated only by the clockwise color-removal sweep.
- Hides the movable anchor artwork as soon as frame positioning is locked.
- Added explicit Grid, Horizontal, and Vertical arrangements to the Appearance page.
- Kept the 1.2.6 protected-aura, sound-performance, compatibility-command, and click-casting fixes intact.

## 1.2.6
- Coalesced deferred combat updates into a single secure-binding, layout, aura-style, sound, and visual refresh pass.
- Added visual-state caching so unchanged cells no longer rewrite their textures and borders on every event.
- Added detailed native sound diagnostics: active handles, additions, removals, reuse, batches, elapsed time, instance context, and a high-load warning.
- Added contextual help tooltips throughout the General, Appearance, and Dispel pages.
- Made `/cleansive` and `/cls` the conflict-free primary commands. `/dcr` and `/decursive` are registered only when Decursive is disabled.
- Deferred compatibility-alias registration until all enabled addons are loaded and used Retail 12.1's current character-GUID enable-state signature.
- Added `pradd` and `skadd` replacements for the former target-to-list commands.
- Prevented untargeted area abilities and self-only spells from being assigned to secure unit cells or the generated mouseover macro.
- Made AuraContainer failure handling local to the affected unit cell and accepted successful `AddAuraSlot` calls that return no frame.
- Made protected cooldown binding optional so a cosmetic cooldown cannot break an aura slot.
- Restored the generic Bleed fallback for new encounter spell IDs and excluded hostile focus targets from the roster.
- Avoided readable-aura fallback scans while sound alerts are disabled and separated temporary grid visibility from the saved enabled setting.
- Localized native keybinding labels and separated overlapping engine-owned click and stack indicators.
- Kept English as the explicit default language, with French available from the General page.

## 1.2.5
- Fixed disabled dispel types being reclassified as protected slot-1 afflictions.
- Preserved configured dispel priority when readable fallback auras are present.
- Added native keybindings, Escape-to-close support, an AddOns settings entry, and addon-compartment controls.
- Reworked native sound registrations to update only changed unit/spell pairs and added Master, Effects, and Dialog channel choices.
- Added L/R/C click hints, safer contrast for dark class colors, a blacklist-duration control, and automatic blacklist expiry refresh.
- Removed target-change full refreshes, throttled appearance sliders, capped aura history, confirmed destructive list clears, and removed the obsolete options implementation.
- Aligned the generated macro so Ctrl selects the same third spell as Ctrl + left click on the grid.
