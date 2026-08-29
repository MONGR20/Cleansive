# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

## 1.5.43

- **Les boutons souris 4 et 5 sont pris en charge.** Rien de neuf n'y est lie : le bouton 4 lance la troisieme dissipation, deja disponible sur Ctrl + clic gauche, et le bouton 5 pose la focalisation, deja sur Ctrl + clic milieu. Les deux combinaisons les plus penibles a faire en plein combat sont simplement accessibles au pouce. Une souris sans ces boutons ne perd rien, et aucune assignation existante ne bouge. L'infobulle de la grille les decrit, en anglais comme en francais.

*La correspondance est fixe : Cleansive detecte les sorts, il ne propose pas de remapper les touches. Un veritable remappage est un autre chantier, avec son ecran de configuration.*

- Tests : 702 a 713.

## 1.5.42

Cette version ne change aucun comportement. Elle ajoute deux relevés destinés à trancher une hypothèse sur le refus de mise en forme, ouverte depuis la 1.5.40.

- **L'etat reel des restrictions est releve.** La 12.1 connait six types de restriction -- `Combat`, `Encounter`, `ChallengeMode`, `PvPMatch`, `Map`, `Chat` -- exposes par `C_RestrictedActions`. Cleansive n'utilisait que `InCombatLockdown()`, qui ne repond que pour le premier. Or une cle mythique garde `ChallengeMode` actif pendant toute la course, y compris entre les packs, la ou le code se croit libre d'agir. Chaque refus de mise en forme est desormais compte avec l'etat qui avait cours : `/cleansive diag` dira si les 315 refus du 29/08 arrivaient tous avec le verrou de combat baisse et une restriction toujours active.
- **Le client nomme lui-meme ce qu'il refuse.** `ADDON_ACTION_FORBIDDEN` et `ADDON_ACTION_BLOCKED` sont enregistres : ils donnent le nom de la fonction refusee. Jusqu'ici Cleansive devinait ses refus apres coup, en demandant au cadre si l'inscription avait pris. Les deux evenements ne portent aucune restriction, ce que le controle statique verifie contre les definitions de Blizzard. L'evenement concerne tous les addons ; seuls les refus de Cleansive sont enregistres.
- Ces deux relevés suivent la version, comme les autres compteurs.
- Tests : 691 a 702, verifies par reinjection.

## 1.5.41

- **La plaque de la lettre de clic nait cachee.** C'est `StyleAuraVisual` qui decidait de la montrer ou non, et ce stylage peut etre refuse par le client : le releve du 29/08/2026 en compte 690 refus en une session. De toutes les regions du visuel, la plaque est la seule a naitre avec une couleur -- les autres n'ont ni teinte ni texte et ne se voient pas. Un refus au tout premier passage laissait donc un petit carre sombre dans le coin d'une cellule, alors meme que le joueur avait desactive les lettres de clic. La cellule de repli cachait deja la sienne des la creation ; celle du moteur avait ete oubliee.
- Rien d'autre n'est masque par precaution : les autres regions ont ete verifiees une a une et n'affichent rien tant qu'aucune couleur ni aucun texte ne leur est donne.

*Note sur la 1.5.40 : le decoupage de la passe de style en neuf etapes n'a rien recupere. Le meme releve montre 6210 etapes perdues pour 690 refus, soit les neuf a chaque fois -- toutes les regions du visuel sont filles du cadre protege du moteur, donc interdites ensemble ou pas du tout. Le decoupage reste juste face a un refus partiel, mais il ne traitait pas la cause. La corriger demande de reparenter ces regions sur la cellule de Cleansive, ce qui change l'ordre d'affichage et ne peut se valider qu'en jeu.*

## 1.5.40

- **Un refus du client n'emporte plus le reste de la mise en forme.** Le releve du 29/08/2026 montrait `Frames.lua:641: calling 'SetFrameLevel' on bad self (forbidden object)`, 315 fois en une session. `SetFrameLevel` etait la premiere ligne d'un `pcall` qui contenait toute la passe : quand le client refusait ce seul appel, le fond, la bande de type, le compteur de charges et la lettre de clic n'etaient jamais poses non plus. C'est le defaut de police de la 1.5.35 dans un autre bloc -- corrige a l'epoque seulement la ou il avait ete observe, ce qui est exactement pourquoi celui-ci a survecu. Chaque etape tient maintenant seule.
- **Le releve dit desormais combien de la passe a ete perdu**, pas seulement qu'elle a echoue. Une etape sur neuf est une eraflure ; neuf sur neuf est toute la mise en forme. Avant, les deux etaient indiscernables -- parce qu'un seul refus les rendait identiques.
- **Les compteurs sont ramenes a zero quand la version change.** La base du 29/08 portait 630 reports et 315 refus sans aucun moyen de savoir de quelle session ni de quelle version ils venaient : il a fallu les comparer a une copie du fichier gardee par hasard. Chaque nombre est maintenant date par la version qui l'a produit, et le releve l'imprime.
- **Le pic sonore est retenu au moment ou il se produit.** L'instantane est pris a la deconnexion, quand le joueur est seul : 46 inscriptions pour une unite. Le donjon qu'il devait mesurer etait exactement ce qu'il ne pouvait pas voir. Le maximum d'inscriptions et d'unites est desormais releve pendant la session, et une inscription incomplete en groupe compte comme un probleme meme si la fin de session est propre.
- Le champ mort `unlisted`, laisse par la 1.5.37, est purge des bases existantes.
- Tests : 668 a 686. Les deux correctifs verifies par reinjection : 6 rouges avant correction, dont le cablage du pic, qu'une premiere version des tests ne couvrait pas.

## 1.5.39

- **Un enregistrement sonore rate est desormais repris.** Effacer l'empreinte laissait la porte ouverte a une reprise mais ne la demandait a personne : hors combat, sans autre evenement, les sons concernes restaient absents pour le reste de la session. La reprise est bornee a deux tentatives espacees, protegee par le compteur de generation, et se tait en combat, ou la fin du combat demande deja un rafraichissement. Le commentaire qui affirmait le contraire disait faux.
- **Les deux plaques d'etat ne se superposent plus.** Le code affirmait qu'« En attente » et « Sans dissipation » ne pouvaient pas etre necessaires en meme temps, et les posait au meme point. C'est faux : une specialisation sans dissipation peut redimensionner la grille en plein combat, ce qui differe un changement protege et allume les deux. Ce qui est visible est maintenant empile, dans un ordre fixe, et la plaque restante reprend la place liberee.
- **Un refus perime ne se lit plus comme un probleme actuel.** Toute base issue de la 1.5.37 portait encore `refusedEvents.COMBAT_LOG_EVENT_UNFILTERED`, un evenement que la 1.5.38 ne demande plus, et le releve l'imprimait comme si le client venait de le refuser. Les refus qui ne correspondent a aucun evenement demande sont oublies au chargement. En revanche `diag reset` les conserve : ce n'est pas une ligne de rapport, c'est la raison pour laquelle l'addon ne redemande pas -- l'effacer ramenait la fenetre qui propose de le desactiver.
- Priorites, Exclusions et Filtres finissent comme l'Historique : pagination masquee tant qu'il n'y a qu'une page, vidage eteint sur une liste vide, et chevrons repeints quand ils sont desactives. L'action etait deja bloquee ; c'est l'apparence qui mentait.
- `/cleansive diag` figure dans l'aide, distingue l'echec d'un type actif de celui d'un type retire, conserve l'erreur sonore pour apres la deconnexion, et conclut : « Diagnostic sain » ou le nombre de problemes releves. Un report differe n'en est pas un.
- Les accents manquants des chaines de diagnostic francaises sont corriges.
- Tests : 646 a 668. Les quatre correctifs ont ete verifies par reinjection du defaut : chacun rougit la suite avant d'etre corrige.

## 1.5.38

- **The backlash warning added in 1.5.31 is removed.** It was not merely inert -- it was inverted. `AuraContainerUtil.CanApplyIdentityCandidateFilters` refuses `includeSpellIDs` on a harmful aura carried by a unit the player can assist, unless the spell is `NeverSecret`. The warning slot had no other filter, so the yellow ring was drawn on *every* dispellable affliction rather than on the dangerous ones: it told the player not to cleanse, on everything. A safety feature cannot rest on a filter the client is free to ignore.
- **`COMBAT_LOG_EVENT_UNFILTERED` is no longer requested,** and the collector built on it is gone with it. Blizzard's own generated documentation marks the event `HasRestrictions = true`; registering it fires `ADDON_ACTION_FORBIDDEN`, a dialog whose first button disables the addon. 1.5.36 added it and the very next session raised exactly that. Seasonal spell IDs go back to being read from a recorded combat log outside the addon, then confirmed on screen before being typed.
- **Disabling the addon or hiding the grid during combat now says so.** Both were deferred correctly and silently: the option appeared to change and the screen did not. They were written straight to their flags instead of going through `MarkPending`, and the static check could not see it because a business boolean is not the literal `true` it looks for. The flag and the requested value are now separate fields.
- The plate is re-evaluated when the flags are cleared, instead of going out because some refresh path happened to run. Disabling the addon in combat took a path that did not, and the plate outlived its own reason.
- Two new static checks: no event Blizzard marks `HasRestrictions` may be named in the code -- the list is read from `DefinitionsAPI` rather than written by hand -- and the mock now records any aura slot filtered by spell ID alone, which is what made the 1.5.31 ring invisible to 660 green tests.
- `pendingSoundRefresh` is deleted rather than documented for a third time. It was written in two places and read in none; clearing the sound fingerprint is what actually schedules the retry, and the end of combat requests one regardless.
- Three changelog entries carried claims the code had never honoured or no longer honours. They are corrected in place rather than left standing, because a note that has to be disbelieved is worse than no note.
- Tests: 660 to 646. The count went down because two features were removed; what remains covers the client's real rules rather than an assumed version of them.

## 1.5.37

- **A refused event registration is asked for once, not at every login.** The session that followed 1.5.36 raised `ADDON_ACTION_FORBIDDEN` on `Frame:RegisterEvent()` -- a dialog whose first button disables this addon. The refusal does not raise, so nothing could catch it; the frame is now asked afterwards whether the registration took, and a refusal is remembered. 1.5.36 added exactly two events, which is where the fault came from.
- **The pending plate no longer promises a restyle the client has forbidden.** Styling the labels the protected engine owns failed 315 times in one session without a single success, and each failure was announced as if the player had asked for it: the plate stayed lit for the whole of every fight. The deferral remains -- only the promise is withdrawn. This is the same forbidden-object family as the font bug fixed in 1.5.35, reached by a different path.
- The reason for a refused restyle is kept, not just its count. A count cannot tell a forbidden object from a nil field, and that distinction was the whole diagnosis.
- `/cleansive diag` reports both: which event the client refused, and how many restyles it turned down with the first reason.
- Tests: 647 to 660. `RegisterEvent` and `IsEventRegistered` were absent from the mock -- a code that verifies its own registration would have concluded that *every* event was refused, and written that down permanently.

## 1.5.36

- `/cleansive diag` reports what a session leaves behind, and the same record is kept in SavedVariables. Three things earned their place, each because its absence cost an evening.
- **Deferrals now name what caused them.** Explaining why the pending plate appeared during dungeon pulls meant auditing eleven flags by hand against every event that can raise one. A flag now records its count and the event being dispatched when it went up, or `player` when no event was.
- **Afflictions the seasonal sound list has never heard of are collected.** The combat log carries spell IDs for auras `C_UnitAuras` refuses to read; finding one missing meant reading 82 MB of log with grep. Only `SPELL_DISPEL` is inspected, so the busiest event in the game costs one string comparison. Enemy buffs removed by a purge are excluded on `auraType`: in a combat log a purge looks exactly like a dispel, and two of them nearly entered the sound list by hand.
  *Corrected in 1.5.38: `COMBAT_LOG_EVENT_UNFILTERED` is marked `HasRestrictions` by Blizzard and registering it offers to disable the addon, so this collector was removed. "One string comparison" also undersold the cost -- each event resolved an API, ran a `pcall`, unpacked eighteen values and applied two guards.*
- **The engine's own failure table is kept instead of being discarded at logout.** It existed all along and died with the session.
- The dispel type is still not in there. A combat log never carries it -- only the school, which does not separate Magic from Poison or Disease. The recorder narrows the work to one tooltip per affliction; it cannot remove it.
- A new static check refuses a Lua file that the addon loads and no test ever executes, with an explicit list of the two deliberate exclusions. `spec.lua` keeps its own hand-written file list, and it drifts: that is how `EllesmereUX.lua` stayed out of the suite for years, and `Diagnostics.lua` was forgotten in it the same day it was written.
- Tests: 635 to 647. Static checks: 7 to 8.

## 1.5.35

- A font the client refuses can no longer take the whole grid down with it. `ApplyCellFonts` sets a font on the labels the protected engine owns, and in 12.1 the client can declare those forbidden to addon code: `SetFont` then raises. The error aborted `LayoutButtons`, whose *last* line is `pendingLayout = false` -- so the flag stayed raised for the rest of the session, the layout never completed again, and the pending plate lit up on every subsequent fight. Both symptoms, one cause.
- The plate was not lying. It had been reporting a real stuck state correctly since 1.5.28; 1.5.34 silenced the background noise around it, and what remained underneath was this.
- When the client refuses a label, the engine's copy keeps the size it was built with. That is a smaller loss than a grid that never lays out again.
- Found by `!BugGrabber` in a real dungeon -- the first Lua error ever captured from Cleansive in game. Every check until now ran against a mock client, where a forbidden object does not exist.
- Tests: 626 to 635. The new ones reproduce the exact stack, including the consequence the player sees: the plate still lit at the next fight.

## 1.5.34

- The pending plate only speaks about changes you made. It watched every deferred write, including the ones the game raises on its own: `SPELLS_CHANGED` fires on a shapeshift, a mount or an item, `UNIT_PET` and `GROUP_ROSTER_UPDATE` fire unprompted. In a dungeon that lit the plate on nearly every pull, saying "something is waiting" about bookkeeping the player can neither act on nor understand. Reported from a real session, where it appeared with nothing having been changed.
- The work is still deferred and still replayed at the end of combat; only the announcement is withheld. A background event cannot silence a change you are actually waiting on, and the announcement does not stick to a flag from one fight to the next.
- Setting a focus stays announced: it is a deliberate act, and its cell really does wait for the end of the fight.
- Tests: 617 to 626, driven through the real event dispatcher rather than by setting flags by hand -- the wiring between an event and its deferral was what needed proving.

## 1.5.33

- `Fonte d'armure` (1250043) joins the seasonal sound list as a Magic affliction, confirmed in game. It was dispelled seven times in a recorded session and was absent from the list, so no alert ever fired for it. A combat log never carries the dispel type -- only the school, Fire here, which does not separate Magic from Poison or Disease. Any aura found this way needs the same on-screen check before it can be typed.
- `Afflux sanguin` (1254826) is deliberately *not* added, although it appears among the dispels of the same log: it is an enemy buff removed by Tranquilizing Shot, not an affliction on an ally. A test now holds that distinction, because the log makes the two look alike.
- This is the first entry in that list to come from a recorded session rather than from a reference. The list was 5 out of 7 correct for that dungeon, which is the first measurement of its staleness anyone has had.

## 1.5.32

- The grid no longer starts at raid group 1 for everyone. It starts at your own group and wraps: from group 3 the order is 3, 4, 1, 2. When every dispeller sees the same order, they all reach for the same cell first and most of them arrive to find the work already done. Starting somewhere different for each player spreads it with nothing to agree on beforehand. The priority list is still read first and still wins.
- `PlayerRaidGroup` had to be written because the owner's own group was always reported as 1: the subgroup is read out of the unit token, and `player` carries no raid index. It resolves identity through `IsPlayerUnit`, the only guarded path allowed to touch `UnitIsUnit`.
- Nothing changes in a party or a dungeon: everyone is in group 1 there, so there is nothing to spread.
- Tests: 609 to 615. `IsInRaid` and `GetRaidRosterInfo` were wired to "no" and nil in the mock, so no test could place the player in a raid group at all -- the cell order in a raid was verified nowhere. `UnitGUID` now answers with one GUID for a character seen through two tokens, which is what made the deduplication testable.

## 1.5.31

- Auras that punish the dispeller are flagged. Dispelling Unstable Affliction turns its damage on you and silences you; Cleansive painted it like any other magic debuff and invited the reflex. A cell carrying one now gets a warning ring and a `!` on top of its normal click colour. The click is still there -- eating the backlash is sometimes correct -- but it can no longer be made without seeing it.
- The warning survives 12.1's protected auras because it never reads them: a dedicated aura slot is filtered engine-side on `includeSpellIDs`, the same mechanism the seasonal sound registrations already use. It carries the same weakness, and the list is marked with its season for that reason -- an unlisted aura is silently not flagged.
  *Wrong, corrected in 1.5.38: `CanApplyIdentityCandidateFilters` refuses spell-ID filters on a harmful aura carried by a unit the player can assist. The filter was ignored and the slot had no other, so the ring appeared on every dispellable affliction. The feature is removed.*
- A dangerous aura of a type the character cannot clear, or one the player has ignored, is not flagged: the cell would not light up anyway, and a ring pointing at nothing is worse than no ring.
- Tests: 591 to 609. The mock now runs `initializeFrame`, so every visual the protected engine draws -- rings, letters, timers -- is finally executed by the suite instead of being declared and never built. `SetHeight` and `SetWidth` are recorded too: a bar drawn at the wrong thickness, or not drawn at all, used to be invisible to a test.

## 1.5.30

- The priority chevrons pointed the wrong way. The actions were always right -- "move up" moved up -- but the drawing was inverted: the left button showed a downward chevron. Only the sign of the rotation was wrong, and no test could see it because the mock did not record `SetRotation`. It does now.
- The live preview is a faithful reduction of the cell instead of a cropped one. The cell was capped at 26 to 38 px depending on the layout, but its texts were sized *for that cap*: at a real 40 px the click letter was computed for a 26 px cell and covered the cooldown number. Every part of the preview -- letter, number, inset -- now takes the same scale as the cell it stands for.
- Tests: 570 to 591, including the preview at 12, 22 and 40 px.

## 1.5.29

- The six sliders show their value again -- they never showed one. `SetPoint("TOPRIGHT", x, y)` is the three-argument form: it anchors to the parent's TOPRIGHT, so a positive x pushed the number 265 to 575 px past the right edge of the panel. Size, spacing, columns, opacity, blacklist duration and the sound limit were all mute.
- Opacity reads `25 %` instead of `0.25`, and a slider's label now stops where its value begins instead of running underneath it.
- "Cleanse cooldown" and "Native sound budget" describe what they do: "Cleanse spell cooldown" and "Sound alert limit". The option and the live preview use the same words.
- The history page has a real empty state -- a centred title and an explanation -- and its pagination appears only from two pages. "Page 1 of 1" between two dead buttons is furniture, not navigation. Clearing an empty history is no longer offered as an action.
- The priority arrows are drawn from two rotated bars instead of the characters `^` and `v`: readable at rest, class-coloured on hover, clearly dimmed when the move is impossible. They depend on neither a font glyph nor a Blizzard texture path.
- "Hover cleanse key" no longer runs underneath its own button in French, and "Reset positions" has room for its French label.
- A slider's frame was 30 px tall for a 4 px bar, which left 9 px before the next section title. It is 22 now, and the page keeps the 16 px minimum between a group and the heading that follows.
- Tests: 512 to 570. `EllesmereUX.lua` had been excluded from the suite for years as "too frame-heavy for no added coverage"; the mock has since grown enough to run `CreateOptions` unchanged. That exclusion is why six blank sliders survived undetected -- the file was parsed, never executed.

## 1.5.28

- A protected change asked for during combat says so. Blizzard locks layout, roster, bindings and profile work while you fight; Cleansive deferred them correctly and silently, so the option moved and the screen did not. A plate now appears beside the grid for as long as something is waiting, and it goes out when the change lands. It lives on the unprotected layer, which is the only reason it can appear during the fight it is describing.
- A character with no cleansing spell gets an explanation instead of a grid of grey cells that can never light up. The notice only appears once the client has actually answered about the spellbook -- before that an empty book is ignorance, not a fact about the character.
- Every combat deferral now goes through `MarkPending`, and a static check refuses a flag set by hand: a deferral the plate does not know about is exactly the silent state it exists to remove. `pendingSoundRefresh` is the one exception, and it is documented as such -- see below.
  *Not true at the time, corrected in 1.5.38: `pendingEnabled` and `pendingGridVisibility` were written straight to their fields, and the check could not see them because it only matched the literal `true`. Both now go through `MarkPending`, the check matches any value, and the `pendingSoundRefresh` exception is gone with the flag itself.*
- `ApplyPriorityDispelBinding` clears its pending flag when there is no binding owner. The flag was set and never cleared for the session; harmless while nothing read it, but the plate would have stayed lit with nothing able to put it out.
- Tests: 492 to 512, and a sixth static check.

Known, not fixed: `pendingSoundRefresh` is set when a sound registration fails in combat and is never read again -- nothing replays it when the fight ends. It is left alone rather than announced, because a plate nothing can extinguish is worse than no plate.

*Removed in 1.5.38: nothing read it, and clearing the sound fingerprint already schedules the retry that the end of combat performs anyway.*

## 1.5.27

- The engine diagnostic names the type that actually failed. Retired types are reconciled before the wanted ones and both shared a single first-error slot, so a pass that failed on a retired Magic slot *and* on an active Poison slot reported the cell's real fallback with the name of a cleanup operation. Active and cleanup failures are now recorded apart, and each message reads its own.
- Changelog: the test suite is no longer described by a path that only exists on the development machine.
- Tests: 487 to 492. The mock could only fail one slot key at a time, which is exactly why a simultaneous retired/active failure had never been exercised; it now accepts a set of keys.

## 1.5.26

- A superseded retry timer no longer releases the guard a newer one holds. `C_Timer.After` cannot be cancelled, so the stale callback stayed queued and cleared the single-timer flag before checking its generation; a further event could then arm a second timer for the current set. Each schedule now carries a token, and a callback that does not own it returns without touching anything.
- Losing every dispel type no longer strands the retired slots. The retry was gated on a non-empty wanted set, so a character who ends up with no dispel spell -- and whose historical slot failed to be neutralised -- kept it filtering auras with no retry and no warning. An empty set reports every cell ready, so this branch can only fire on a real cleanup failure.
- The diagnostic no longer contradicts itself. When every wanted type was live and only a retired one resisted, the message announced an incomplete engine with `82/82 slots` and a fallback nothing had fallen back to. Cleanup failures now have their own line, counting the retired slots still filtering; the original message is kept for cells that genuinely lost the engine.
- Tests: 470 to 487. The mock ran its timers in one batch, which could not express a stale callback firing after a newer one was armed; it can now run a single timer by index.

## 1.5.25

- Retries are scheduled, not merely allowed. 1.5.24 set a flag and waited for some other spell event to call the reconciliation again, so a single transient failure could leave cells on the Lua fallback for the rest of the session. A bounded timer now drives them, guarded by a generation so a change of type set cancels the pending one, and deferring to `PLAYER_REGEN_ENABLED` if it fires during combat.
- A failed neutralisation counts. Readiness only looked at the wanted types, so a retired type left analysing auras raised no retry at all. The pass now reports two outcomes: whether the cell can use the engine, and whether the pass was complete.
- The retry budget starts again for each new type set, and the warning prints once per generation rather than once per attempt -- four identical lines in the chat frame, where the 1.5.24 notes promised one. The slot counter adds every configured slot instead of only whole ready cells, which could report `0/246` while 164 slots were live.
- Tests: 465 to 470. Writing the autonomous-recovery test immediately found a fifth defect of my own: the single-timer guard blocked rescheduling when the generation changed, so the stale timer no-opped and no new one was ever armed.

## 1.5.24

- A retired dispel type actually stays inert. 1.5.23 replaced its filters with an empty table, and `ConfigureButtonAuraContainer` handed the real ones straight back -- it walks every accumulated slot key and runs on every layout, roster assignment and filter edit, so the claim in the 1.5.23 notes did not hold in the final state. The active set is remembered now and consulted wherever slot filters are applied.
- A failed slot reconfiguration is diagnosed and retried instead of being permanent. The wanted set was stored before the cells were reconciled, so a cell that failed was left on the Lua fallback and the next call returned early without retrying it -- until a reload. Failures are recorded, reported once, and retried up to three times; the retry is owed when containers exist but are not all covered, because a filter that fails for one slot fails it on all 82.
- Tests: 452 to 465. The mock recorded nothing for `SetAuraSlotCandidateFilters` and could not fail it, which is the root of both defects above: the generic stub answered success and the suite could not see either one. It now stores the filters and can be made to fail.
- README: the layout modes no longer promise a single row or column, and the hover-cleanse key is described as what it is -- it casts the first configured spell on mouseover, target, then player. It never picks an afflicted unit.

## 1.5.23

- Aura containers are reused instead of replaced. Hiding a container does not destroy it -- WoW keeps every frame for the session -- so each real change of the dispel-type set left a generation of 82 abandoned containers behind, and the cost grew with every talent or specialization change. A change now reconciles what is already there: a new type gains a slot, a type that is no longer needed has its filters replaced by an empty `includeDispelTypes` table, and a type that comes back gets its real filters again. The total is bounded to 82 containers and at worst 410 slots for the whole session. Ten class alternations now allocate nothing at all, which is the measurement three audits had asked for.
- The visual side needed nothing: `StyleAuraVisual` reads `typeToSlot` and `manualTypeSpell`, so a type the character can no longer clear was already styled invisible.
- The README no longer duplicates the whole changelog. It carries the current release and points at `CHANGELOG.md`, which takes the readme from about 48 KB to about 8.5 KB.
- A fifth static check refuses the tooltip sentences that were corrected in 1.5.22. A behavioural test guards what the code does; only a text rule stops a wrong sentence from coming back.
- Tests: 451 to 452.

## 1.5.22

- Two tooltips said the opposite of what the code does. "Enable or disable Cleansive without changing your saved settings" was wrong -- `SetEnabled` writes `db.enabled`, which is stored in the character and specialization profile; it now says so. The layout tooltip still promised one horizontal row or one vertical column, which stopped being true in 1.5.18 when both modes started wrapping rather than running off the screen.
- Tests: 448 to 451, guarding the behaviour the enable tooltip now describes.

Not changed: the audit recommends reconfiguring aura containers through `ClearAuraSlots` and `UnregisterAuraSlot` rather than replacing them. Those exist only on Blizzard's private mixins. What a `CustomAuraContainerTemplate` exposes to an addon is `AddAuraSlot`, `SetAuraSlotFilterString`, `SetAuraSlotCandidateFilters` and `SetAuraSlotSortMethod` -- a slot can be added and reconfigured, never removed. Reusing containers therefore means never destroying them and styling the unwanted types invisible instead, which is a change to the protected path and is being weighed separately.

## 1.5.21

- The grouped badge's space is reserved before the rows are chosen, not after they are placed. 1.5.20 picked the row count against the whole height and only then slid the grid to save the badge, so the last row went off the bottom by exactly the amount the badge was rescued by. Only what the correction would actually take is subtracted, so a grid whose badge already fits keeps its full height.
- "Spellbook resolved" is an explicit state rather than a guess from the table's contents. Testing for a non-nil table made the boot fallback unreachable in 1.5.19; testing for a non-empty one in 1.5.20 then kept the cautious class-wide slot set for a whole session on a character who genuinely knows no cleanse. The client confirms readiness on `PLAYER_ENTERING_WORLD` and `SPELLS_CHANGED`, and an empty answer after that is a real answer: no spells, no engine slots.
- Tests: 435 to 448.

Not changed: `usesAuraEngine` has been reported twice as an accidental global. It is not one -- `Frames.lua` forward-declares it as a local on line 7. Settled by loading the addon in the test VM and reading `_G`, which returns nil.

## 1.5.20

- A reset asked for during combat recomputes the grid, not just the position. `ResetPositions` deferred the move to the end of combat but set no layout flag, so the position returned to the default while the wrap stayed the one computed for the old corner -- a narrow wrap from a screen edge became a long run off the middle of the screen.
- The automatic on-screen correction is no longer one-way. 1.5.18 claimed the grid would return to the chosen position once the group or the cells shrank; it never did, because the next layout started from the already-corrected anchor and found nothing to correct. The layout now restores the saved position first and recomputes the correction from there, so the grid comes back on its own.
- The grouped badge is inside the bounded rectangle. It is anchored on the far side of the anchor, a full cell plus 4 px opposite the growth direction, and only the cells were being measured -- a grid that fit perfectly going down could still push its badge off the top edge.
- Engine slots reserve only the types a spell can currently clear. `enhancedTypes` were merged in whether or not the talent behind them was taken, so a priest without 390632 paid for a Disease slot on all 82 buttons, and a monk without 388874 for two.
- The boot fallback that keeps the class-wide set until the spellbook answers now exists. It was written against `knownSpells ~= nil`, but `UpdateSpells` clears that table on entry, so the branch was unreachable and the safety described in 1.5.19 was not real.
- Tests: 422 to 435.

## 1.5.19

- Protected aura slots follow the spells the character actually knows. The filter accepted every definition belonging to the class without ever checking the spellbook, so a class whose definitions span five dispel types reserved a slot for all five on all 82 buttons -- 410 protected frames for an evoker who knows one cleanse, where 82 are needed. Learning a spell widens the set on the next spell update, and the class-wide set stays as a boot fallback in case the spellbook is not ready: an empty set would strip the cells of the protected engine, and 1.5.4 already showed what removing a signal costs.
- Tests: 418 to 422.

## 1.5.18

- The grid is laid out again whenever the anchor moves. Since 1.5.17 the cell count depends on where the anchor sits, but dragging it, resetting it or switching profile never recounted, so a run computed at the centre kept its centre-sized wrap once dragged towards an edge -- a cell ended up 2738 px across on a 1920 px screen. Two orderings were inverted as well: `LayoutButtons` read the anchor's edges before the new profile's position had been restored, and the anchor was resized after its edges had been measured.
- Both axes are bounded, and the wrap is computed from the cells actually shown. A capped row still wraps downwards and a capped column still wraps sideways, so bounding only the primary axis left the fold free to walk off the other edge. Folding on the full pool of 82 buttons also shrank a five-man grid as if it had to hold a raid; buttons past the roster are hidden and never seen.
- When the anchor sits against the edge the grid grows towards, the grid slides back into view. No wrap can help there: the space is worth about thirty cells and a raid needs eighty. The saved position is deliberately left untouched -- this is a display-time correction, so the grid returns to the chosen spot by itself once the cells shrink or the group does.
- One click hint, always in the same corner. Each aura type used to get its own, shifted sideways so two visuals would not print over each other, but three plates need 46 px with their margin and the largest cell is 40 -- the Ctrl letter could never be drawn at all. The aura level already encodes type priority, so stacking every hint in one corner puts the winning letter on top by construction. The guard also counts the plate's own 1 px anchor offset, which it had been ignoring: the second hint spilled by a pixel at 12 px and the third did the same at 39 while being hidden at 40.
- Saved settings: a non-boolean falls back to its default instead of being read for Lua truthiness -- `"false"`, `"non"` and `0` are all truthy, so a database saying `locked = "false"` came back locked. `typeOrder` is rebuilt without duplicates or unknown names and with nothing missing, and `enabledTypes` is cleaned of entries that no longer exist.
- Tests: 354 to 418. The suite only visited corners opposite the growth direction -- the favourable ones -- and never moved the anchor after a first layout, which is why none of the above turned it red.

## 1.5.17

- Name and class reads are guarded like GUIDs were. 1.5.14 protected `UnitGUID` and `UnitIsUnit` and assumed that was the whole class of problem; `UnitName`, `UnitFullName` and `UnitClass` are marked secret-capable too, and the roster read all three raw -- a concatenation for the qualified name, an `or` for the display name, a direct read for the class. An unreadable name now falls back to the unit token, an unknown identity matches no priority or skip entry without dropping the unit from the roster, and `/cleansive pradd` refuses rather than recording an entry that can never match. The static rule covers all six APIs.
- Layout limits are measured from the anchor, not from the whole screen. The 1.5.15 cap was only correct when the anchor sat against the opposite edge: from a centred anchor it allowed roughly twice the cells that fit, and the far half of a raid was still drawn off screen -- the exact defect 1.5.15 announced as fixed. The count is exact now, including the layout's own 3 px margin and the last cell's own width.
- The 1.5.16 sweep that turned the stack counter off in every existing profile is removed. A migration may repair invalid data or a feature that no longer exists, but the stack counter is still supported and still has its button, so the sweep erased a choice players had deliberately made. Databases already touched by 1.5.16 cannot be recovered. The new default applies to new profiles only, which is what a changed default means.
- Click letters are off by default, without touching anyone's setting.
- Saved settings are validated further: anchor points are checked against the nine WoW accepts, coordinates are repaired, slider values are rounded to whole steps, and booleans that arrived as something else are normalised. Restoring a position falls back to the default rather than raising, so a broken database can never stop the addon from starting.
- The options preview follows the same label sizes as a real cell and only shows the cells that fit its box; three cells at the vertical cap ran 11 px past the bottom with nothing to clip them.
- Click-hint offsets scale with the cell instead of a flat 7 px, and a hint that still would not fit is not drawn. Writing this as a property -- every drawn hint fits its cell, across all 29 sizes and 3 slots -- established that the third hint fits no size at all: three plates need 45 px and the largest cell is 40. That settles the audit's "show a single hint" recommendation by geometry rather than by decision.
- Tests: 248 to 354. (An earlier printing of this entry said 280; 1.5.16 shipped with 248.)

## 1.5.16

- Cell labels scale with the cell instead of carrying a size tuned for the default 22 px. At 12 px the click-hint plate alone covered most of the cell -- it was a fixed 11x11 texture -- and the labels overlapped; at 40 px the same labels floated in empty space. Every size is now derived from the cell and clamped at both ends, calibrated so a 22 px cell is unchanged to the pixel. The unit name is hidden below 16 px rather than drawn as two illegible letters, and the grouped badge follows the same rule since it already resized with the cell.
- The cell is stripped to what it needs: type colour, the affliction's clock sweep, and the numeric dispel cooldown. The affliction stack count keeps its option but is off by default, and one sweep turns it off in existing profiles -- flipping the default alone would have left every current player looking at the number it is meant to remove. A deliberate choice made afterwards is left alone. The unit name is unchanged: it was already off by default.
- Tests: 229 to 248. The harness records fonts, sizes and anchors now, which is what makes a computed layout checkable without a renderer. One test passed for the wrong reason and was repaired: the harness neutralises `GetUXFont`, so the code under test returned early and asserted nothing.

## 1.5.15

- The horizontal and vertical layouts stay on screen. Horizontal forced 82 columns and vertical a single one, so a full raid with pets laid a strict run of about 2 100 pixels -- past the edge of a 1920x1080 screen in both directions. `SetClampedToScreen` only holds the small anchor in place; the cells themselves walked straight off. A run now wraps at what the screen can actually show, without changing the shape that was asked for: horizontal still fills a row before starting another, vertical still fills a column. The grid layout follows a narrow screen the same way.
- Saved settings are validated on load, not merely completed. `applyDefaults` fills what is missing, so a value that was present but wrong -- a string where a number belongs, an opacity outside its slider, a layout mode that no longer exists -- survived it and reached `CreateFrame`. Numbers are now clamped to the bounds the option sliders enforce and unknown enumerations fall back to their default, so a repaired profile always lands somewhere the interface can represent.
- Tests: 217 to 229. Both fixes were verified by removing them and watching the suite turn red. One case the audit raised, a truncated saved position, turned out to be covered already: `applyDefaults` recurses into sub-tables. The test stays as a guard.

## 1.5.14

- `UnitGUID` and `UnitIsUnit` are guarded everywhere. Both are documented secret-capable -- `SecretWhenUnitIdentityRestricted` and `SecretWhenUnitComparisonRestricted` -- and their results were used raw in twelve places: in an `or`, in a comparison, as a table key, and once under a direct `not`. The grouped-indicator cache did all three at once, on the `UNIT_AURA` path, in combat, which is where an error becomes an error flood. Everything now goes through `NS:SafeUnitGUID` and `NS:IsPlayerUnit`; unreadable means unknown and falls back to the unit token. Without a readable GUID a recycled token cannot be told apart, so those units are rescanned every pass rather than trusted.
- The charge-versus-cooldown choice now asks `SpellChargeInfo.isActive` and `SpellCooldownInfo.isActive`, both documented `NeverSecret`, before falling back to reading `IsZero`. This settles the case 1.5.12 could not: a spell whose charges are all banked while a school lockout runs its normal cooldown. The empty charge object used to win there and `clearIfZero` wiped the number off a spell that was genuinely unavailable. Nothing is inferred from an unreadable value any more.
- A cell releases its remembered click slot as soon as the spell reads as ready again. The release keys on a readable `active == false`, which only became available with the flags above; until now a slot could stay attached to a cell until combat ended.
- Tests: 200 to 217, and a fourth static check. The mock can now simulate restricted identity and comparison independently of secret auras, and the spell-activity flags. One case cannot be covered by behaviour at all -- a Lua table is a valid table key, so the mock cannot reproduce what the client raises -- so a static rule forbids calling `UnitGUID` or `UnitIsUnit` outside their two guards.

## 1.5.13

- Removed Will of the Forsaken (7744) from the spell table. It could never light anything, and that is provable without a game test. Cleansive's "Charm" is not a dispel type -- Blizzard's own `AuraUtil.DispellableDebuffTypes` stops at Magic, Curse, Disease, Poison and Bleed -- it is the state "this ally is mind-controlled", detected because you can suddenly attack them, and answered by a crowd-control spell cast on them. A self-only racial fits none of that: it gets no click slot, so the detection is never reached, and `UnitCanAttack` is false on yourself, so your own case never fires either. Listing it only promised an undead player of a class with no crowd-control spell a type that stays dark forever. Nothing changes for anyone who has a real one.
- Tests: the mixed-scope cases now inject the self-only side. No real character carries an area-only and a self-only cleanse at once any more, and pretending otherwise would have quietly turned those assertions into decoration.

## 1.5.12

- 1.5.11 shipped the defect it meant to fix. `C_Spell.GetSpellCharges` is documented to return nil for a spell that is not charge-based, and the fix tested for exactly that. The live client returns a table for those spells too, with `maxCharges = 1`, so every spell was treated as charge-based and the numeric cleanse cooldown stayed missing. The test passed because the mock had been written from the documentation rather than from the client. It now returns what the game returns, and the case turns red without the fix.
- Charge detection uses `maxCharges > 1`, the same test Blizzard's own code uses. That field is documented `NeverSecret`, so it stays readable inside an instance, where the rest of the cooldown state is protected and where this bug lives.

## 1.5.11

- The numeric cleanse cooldown came back on cells for spells that have no charges. Since 1.5.3 the charge-recharge duration object was preferred whenever it could not be read as zero, and in restricted combat its `IsZero` is secret. A spell like Cleanse, which has no charges at all, therefore handed `SetCooldownFromDurationObject` an empty object with `clearIfZero` set, and the frame was wiped. The affliction sweep stayed, because a different frame draws it, so the symptom was "only the number disappeared". `C_Spell.GetSpellCharges` documents a nil return for a spell that is not charge-based; the answer is resolved in `UpdateSpells`, which never runs during combat, so it is read while it is still readable and remembered on the spell definition. The charge object is now preferred only for a spell that actually has charges. Reported from the game, and confirmed by `/cleansive cdstatus` answering "source charge, active nil, applied true".
- Tests: 198 to 200. The charge path had one case, and it used a spell declared to have charges with a readable state -- the exact combination that cannot fail. The new case reproduces the reported one: no charges, unreadable `IsZero`, restricted combat.

## 1.5.10

- Repaired the grouped-manual migration for real 1.5.8 databases. The previous marker had already been consumed after visiting only the logged-in character, so 1.5.9's corrected loop never ran for existing 1.5.8 users. A distinct marker now performs one complete sweep across every character and specialization.
- Made grouped-indicator states deterministic. Every active alert restores the dark plate, coloured outline, exclamation mark, and count; the inactive state clears all of them instead of retaining stale alert colours.
- The "Show names" option immediately restyles protected AuraSlot visuals, matching the stack and click-hint options.
- Realm-qualified priority and skip entries require an exact full-name match. Legacy entries saved without a realm retain their short-name fallback without merging two current cross-realm players.
- Deduplicated active vehicle tokens from the pet portion of the roster. The owner descriptor wins, so enabling pet scanning no longer risks two cells resolving to the same vehicle.
- Combat-only filter transitions now queue a grouped-indicator refresh even when no `UNIT_AURA` follows combat start.
- Manual-only readable cells retain their unit name in afflicted-only mode instead of requiring a secure click slot that those abilities cannot have.
- Filter IDs are sorted numerically, and the French seasonal-sound status uses the formal register consistently.
- The Cleansive logo now replaces the generic dispel spell icon in WoW's addon list and addon compartment.
- Tests: 176 to 198, adding exact reproductions for the 1.5.8 migration state, badge visual transitions, cross-realm names, vehicle deduplication, combat-filter refreshes, and manual-cell names.

## 1.5.9

- The version now comes from the `.toc` through `C_AddOns.GetAddOnMetadata`. It was a second literal in `Core.lua`, and it drifted: 1.5.8 shipped with the options sidebar still advertising v1.5.7.
- The 1.5.5 opt-in migration reaches every character. Its marker was global but the sweep visited the logged-in character only, so the first login consumed it on behalf of every alt, who kept the 1.5.4 value forever.
- The grouped-indicator tooltip no longer promises a sound that always fires. A protected spell ID outside the seasonal list, or past the registration budget, stays silent; the text now says "may still trigger" instead of "still fires".
- The grouped indicator is a badge, not a cell that answers to nothing. It was a `Button` with the mouse enabled, painted as a filled block exactly like an afflicted cell, and no click did anything. It is now a plain frame with a dark plate and a coloured outline, clicks pass through to whatever sits underneath, and the tooltip opens by saying it is not clickable.
- The indicator colour follows the configured type order across the whole group. The aura loop sat outside the type loop, so the colour came from whichever affliction WoW happened to return first; priority was then resolved per unit, so the first afflicted unit won over a higher-priority type elsewhere.
- Scope is applied per ability instead of to the set. One area type widened the scan for every type, and a self-only ability then counted allies it can never help.
- Roster scanning is cached per unit. Every `UNIT_AURA` re-read the whole roster -- up to 82 units times 40 auras, ten times a second in the worst case -- to answer a question a single unit had changed. Ten events on a 40-player raid now cost 10 unit scans instead of 400. The cache is dropped on a roster, profile, spell or filter change, and an entry is only trusted while its unit GUID holds, so a recycled token never inherits the previous player's affliction.
- "%d allies affected" produced "1 allies affected". Both languages now read "Affected units: %d".
- Rewrote the French section of the README, which still described English as the default language -- the behaviour 1.5.8 had already changed.
- Packaging: every tracked file is back to normal permissions. The repository carried the executable bit on all fifteen of them.
- Tests: 122 to 176. The post-combat deferral is now exercised rather than asserted to exist -- the two cases it replaced only checked that a function was defined. The harness gained a controllable protected aura engine, so container rebuilds, partial failures and the Lua fallback can be reproduced. Three static checks run alongside: every Lua file must parse (the two UI files were never loaded before, and they are 27% of the code), no element may be anchored on a slider's bar, and no glyph may fall outside what the interface font can draw. Every fix in this release was verified by reintroducing the defect and watching the suite turn red.

## 1.5.8

- The interface language now follows the WoW client on a fresh install. Until 1.5.7 an unset language fell back to English on every client, so a French player saw English labels next to the French spell and class names the game API returns. It read as missing translations; the French strings had been complete all along. A language the player chose explicitly still wins over the client.
- Unified the French wording on the formal register used by the French game client. Twenty-one strings mixed the two forms, sometimes within the same page.
- Normalised French apostrophes to the typographic form. The file mixed both.
- The resize note no longer sits on the columns and opacity sliders. A slider anchored at y draws its frame from y-25 to y-55; the note was anchored at -286, inside the second row's band. Present in English too, and reported from the game.
- Tests: a static layout check flags any element anchored inside a slider's band in the same column. It catches this and the 1.4.7 overlap between the sound budget slider and the Quick tools heading, neither of which the mock or the game reports. A further test asserts that every English locale key has a French counterpart, since the lookup falls back to English without a word.

## 1.5.7

- Replaced every glyph the interface font cannot draw. Arrows, bullets, a check mark and a quarter-circle all rendered as empty boxes, which made the growth selector unreadable: it showed "[] then []" and gave no way to tell which direction was selected. Reported from the game; no amount of reading the code would have shown it.
- Growth directions are spelled out ("Right, then down") and moved into Locale.lua, replacing the last private label tables outside it.
- The grouped indicator no longer anchors itself twice. Placement lived both at creation, hardcoded above the grid, and in the layout pass that honours the growth direction; until the second ran, it sat on the first cell in the upward layouts.

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
