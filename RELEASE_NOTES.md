# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

## 1.6.38

**`AddAuraSound` est refuse en combat, et l'addon l'appelait quand meme.**
Releve de la 1.6.36 : **210 actions bloquees** `UNKNOWN()`, contexte
`lock=1 / Combat,Encounter,Map,Chat`, pile dans `registerBatch`. Un familier
invoque en plein combat demandait un rafraichissement du registre sonore, la
minuterie de 0,10 s le lancait en combat, et chaque `AddAuraSound` produisait
une action bloquee. Le `pcall` absorbait le retour Lua ; il n'empechait ni
`ADDON_ACTION_BLOCKED` ni `!BugGrabber`. La suite ne voyait rien : son bouchon
autorisait toujours l'appel.

- Les AJOUTS sont reportes tant que le verrou de combat -- ou Encounter, par
  precaution -- est actif. La garde est relue avant CHAQUE lot, pas seulement le
  premier : les lots s'etalent sur plusieurs images et le combat peut commencer
  entre deux.
- Les alertes en place restent en place. Un changement de canal en combat
  attend ; tout ce qui sonnait continue de sonner.
- Aucune reprise aveugle sous restriction : la levee passe par
  `FlushCombatUpdates`, qui demande deja un rafraichissement.
- Le rapport distingue un report d'un echec : `soundDeferred adds=N context=...`.
- Le bouchon refuse desormais `AddAuraSound` la ou les releves ont montre un
  refus, et compte chaque action bloquee. Neuf assertions le prouvent.

**Ce que la 1.6.38 ne fait PAS, a dessein.** L'audit recommandait d'attendre
un masque de restrictions nul avant tout ajout. Le releve de la 1.6.34 dit le
contraire : 46/46 alertes posees sous `lock=0 / ChallengeMode,Map,Chat`, zero
action bloquee. Map et Chat sont actives dans 100 % des contextes releves et
ChallengeMode d'un bout a l'autre d'une cle : attendre un masque nul aurait
tue les alertes pendant toute la cle. La garde porte sur ce qui refuse. Un test
tient cette decision -- la regle « masque nul » fait perdre ses 46 alertes a la
cle -- et si un releve montre un refus sous un autre type, on l'ajoute a la
liste, elle est faite pour ca.

Verifie par trois injections : la garde retiree rend 46 actions bloquees par
scene ; la regle « masque nul » rend une cle muette ; une reprise aveugle apres
report est attrapee.

- Tests : 1 796 a 1 819.

## 1.6.37

**Relecture du chantier masque, de la 1.6.34 a la 1.6.36.** Trois choses que
j'aurais changees en le relisant a froid, changees.

- Le compteur s'appelle desormais `styleRetry retried=N recovered=N`. « granted »
  promettait « une chance donnee » alors que, depuis la 1.6.36, il mesure les
  tentatives reellement rejouees. Une etiquette qui ne dit pas ce qu'elle
  mesure, c'est la lecon de la 1.6.32 ; elle vaut aussi pour le rapport. Un seul
  appel par issue, qui dit si elle a abouti -- le double appel pour une reussite
  invitait a compter deux fois.
- Le rearmement du report vit dans une minuterie, hors distribution
  d'evenement : le releve l'attribuait **au joueur**. Il dit maintenant
  `RESTRICTION_RELEASED`.
- Le commentaire de `RestrictionReleasedSince` s'etait retrouve au-dessus de
  `hasBit` quand les aides de masque ont ete inserees entre les deux.

Ce qui n'a PAS ete change, a dessein : la relecture du masque a chaque refus
(bornee au chemin d'echec), l'union des masques en attente qui sur-approxime
(une passe pour rien, jamais un refus, et un nombre qui ne fait que
sur-approximer ne peut pas deriver), et les deux bits qui representent le
combat (l'API de restriction est neuve en 12.1).

- Tests : 1 795 a 1 796.

## 1.6.36

**Le drapeau d'attente etait un booleen, et le mauvais flux le consommait.**
Correction d'un defaut introduit en 1.6.34 et passe au travers de la 1.6.35.

La sequence, telle qu'elle se produisait en clé :

1. une region refuse sous `ChallengeMode` ; la marque et le report sont poses,
   correctement ;
2. le combat se termine, `ChallengeMode` tient toujours ;
3. le flux de sortie de combat consomme `pendingAuraStyle` sans condition ;
4. la passe de style atteint la region, qui refuse a juste titre d'etre
   retentee -- rien n'a ete libere ;
5. aucun echec neuf, donc rien ne rearme le report ;
6. **a la fin de la cle, le flux ne trouve plus rien a faire.**

La marque savait que `ChallengeMode` etait tombe. Plus personne ne venait le lui
demander. Selon la region, une couleur, une lettre, un nom ou une pile pouvait
rester absente jusqu'a un changement d'option ou un `/reload`.

- L'addon tient desormais **l'union des masques en attente** : un seul nombre
  qui dit quelles levees sont encore attendues. Le report n'est rearme que
  lorsque l'une d'elles tombe vraiment. Le correctif simple -- restyler a chaque
  fin de combat -- aurait ramene les passes que la 1.6.34 venait de supprimer.
- Les bits tombes sont retires de l'union AVANT la passe, pour que les refus
  qu'elle produit la reconstruisent avec leur propre masque.

**Et le compteur de la 1.6.35 comptait double.** Il lisait les autorisations ;
l'indice de clic passe par quatre gardes pour une seule operation, donc une
reprise d'indice affichait deux chances accordees. Il lit maintenant les
**issues** : une operation aboutit ou echoue une fois, jamais deux.
`RegionUsable` redevient une lecture pure, sans effet de bord.

Verifie en reinjectant les deux defauts : le rearmement retire fait tomber le
test du cycle complet, le compteur relu sur les autorisations fait passer
l'indice a deux chances pour une reprise.

- Tests : 1 788 a 1 795.

## 1.6.35

**Le compteur demande, et ce qu'il a fait tomber.**

Le releve du 1er septembre sur la 1.6.34 montrait 567 refus contre 7 602 -- la
1.6.34 tenait -- mais aucune ligne « lock=0 / none » apres la fin de la cle.
Deux lectures possibles, que le rapport ne distinguait pas : les regions ont ete
retentees et ca a marche, ou aucune tentative n'a eu lieu et elles sont restees
eteintes. Le silence avait la meme tete dans les deux cas.

Le rapport porte desormais une ligne de plus :

    styleRetry granted=<n> recovered=<n>

« accordees », les regions a qui une levee a rendu une chance ; « reprises »,
celles qui l'ont saisie.

**Et en la posant, un defaut est tombe.** Une tentative qui reussissait
n'effacait pas sa marque. Consequence : la marque de la cle d'hier -- prise sous
ChallengeMode, Map et Chat -- aurait bloque la region a la cle de demain **sans
jamais la retenter**, puisque les memes restrictions auraient ete actives et
qu'aucune n'aurait « ete levee depuis ». La region serait restee eteinte d'un
bout a l'autre, et pas un seul refus au releve pour le dire.

Une reussite efface donc la marque. Le compteur ne se serait d'ailleurs jamais
stabilise sans cela : il se serait rearme a chaque passe.

Verifie en reinjectant les deux defauts separement : la marque qui survit fait
tomber deux tests, la chance non comptee un troisieme.

- Tests : 1 783 a 1 788.

## 1.6.34

**Une levee ne rejoue que ce qu'elle libere vraiment.** Le relevé du 1er
septembre, en jeu sur la 1.6.33 : 7 602 refus, et **pas un seul** sans
ChallengeMode active. Une cle mythique la garde d'un bout a l'autre ; elle n'est
jamais tombee de la session.

Les compteurs par region portaient la signature du defaut : 360 pour trois
d'entre elles (6 x 60), 300 pour deux autres (5 x 60), 720 pour une sixieme
(12 x 60). Une soixantaine de tours -- le nombre de sorties de combat et de
fins de rencontre pendant la cle. A chacune, l'addon ouvrait une « generation »
et redonnait une chance a TOUTES les regions refusees, y compris a celles que
ces levees ne liberaient pas. Elles echouaient, etaient re-marquees, et le tour
recommencait au pack suivant.

La 1.6.31 avait raison de compter toutes les restrictions. Elle avait tort de
traiter n'importe quelle levee comme liberatrice.

- La marque n'est plus un numero de generation mais le **masque des restrictions
  actives au moment du refus**. La region redevient tentable quand l'une
  d'ELLES tombe, pas quand n'importe laquelle tombe. Une sortie de combat sous
  ChallengeMode ne libere rien : elle ne rejoue rien.
- Le masque n'est relu qu'a deux endroits : au moment d'un refus, et quand le
  travail differe s'execute -- donc apres la distribution de l'evenement, la ou
  l'API repond de nouveau. C'est la propriete que la 1.6.33 venait d'epingler.
- La lecture par region reste arithmetique : elle passe sur chaque region de
  chaque case a chaque rafraichissement, elle doit rester gratuite.
- `AnyRestrictionActive` n'avait plus d'appelant. Retiree.

Verifie en reinjectant le defaut : sur douze cycles de combat et six
rencontres, un seul refus en devient trente-huit. Trois tests virent au rouge.

- Tests : 1 778 a 1 783.

## 1.6.33

**Rien ne change dans l'addon.** Aucune ligne de ce que WoW execute n'est
touchee : cette version corrige un test qui promettait plus que ce qu'il
verifiait.

L'assertion posee en 1.6.32 s'intitulait « le travail est differe, jamais fait
pendant la distribution » et ne controlait que la presence d'une minuterie. Un
code qui aurait travaille pendant l'evenement **et** pose une minuterie l'aurait
donc passee sans broncher -- exactement le defaut qu'elle etait censee
interdire.

Elle compte maintenant les appels : zero juste apres l'evenement, un apres la
minuterie. La fonction sondee est reposee meme si une assertion leve, sinon un
echec contaminerait le reste de la suite. Verifie en injectant le defaut : trois
tests virent au rouge, dont un plus ancien.

- Tests : 1 776 a 1 778.

## 1.6.32

**Les deux dernieres remarques de l'audit de la 1.6.31**, toutes deux mineures,
plus une propriete que cet audit a mise au jour et qui meritait d'etre epinglee.

- Le commentaire au-dessus de `NoteRegionRefusal` portait encore le raisonnement de la 1.6.30 -- « hors verrou de combat, les rejouer ne pouvait rien donner » -- juste au-dessus du code qui le corrige. Il dit maintenant la regle reelle : sous au moins une restriction, on rejoue a sa levee ; sans aucune, le refus est definitif.
- Un scenario de test declenchait une sortie de combat sans drainer sa minuterie. `mock.reset()` vide la file, pas les drapeaux que l'addon a poses dessus : le scenario SUIVANT aurait vu `OnCombatEnded` sortir immediatement. Le drapeau est remis a zero pour tous les scenarios.

**Et la propriete epinglee.** Blizzard documente que
`IsAddOnRestrictionActive` rend **toujours faux** pendant la distribution de
`ADDON_RESTRICTION_STATE_CHANGED`. Restyler depuis cet evenement classerait donc
« definitif » un refus encore temporaire : les autres restrictions repondraient
faux elles aussi. Ce qui nous protege est le report par `C_Timer` -- une
propriete indirecte, que rien ne tenait. Un test la tient : le travail doit
etre differe, jamais fait pendant la distribution.

- Tests : 1 774 a 1 776.

## 1.6.31

**« lock=0 » ne veut pas dire « aucune restriction ».** La 1.6.30 tranchait sur
le seul verrou de combat : refus sous verrou = temporaire, refus hors verrou =
definitif. Le releve du 31/08 disait deja le contraire, dans la ligne meme que
j'avais ecrite pour ca :

```
styleContext lock=0 / ChallengeMode,Map,Chat  count=5571
```

Cinq mille cinq cent soixante-et-onze refus hors verrou de combat, avec trois
restrictions actives. Une cle mythique garde `ChallengeMode` d'un bout a
l'autre, y compris entre les packs -- exactement la ou l'addon se croit libre.
La 1.6.30 les condamnait donc definitivement, et une couleur ou une police
refusee pendant la cle ne revenait plus apres.

- **Toute restriction compte**, pas le seul verrou de combat : `Combat`, `Encounter`, `ChallengeMode`, `PvPMatch`, `Map`, `Chat`. Un refus sous restriction porte la **generation** courante et donne droit a UNE nouvelle tentative quand la restriction tombe -- pas une par passe. Un refus sans aucune restriction reste definitif.
- `ADDON_RESTRICTION_STATE_CHANGED` et la fin du combat ouvrent cette generation.

**Tous les chemins passent enfin par la meme regle.** Le niveau de cadre,
l'etat de la souris, l'indice, sa plaque, le balayage de duree et la couche de
libelles avaient chacun leur variable, ou aucune. Une region, une cle, un
helper. La plaque, notamment, etait marquee refusee sans que sa marque soit
jamais relue.

**L'empreinte d'import voyait « table » partout.** Les types actives, l'ordre
des types, les combinaisons de clics et les deux listes d'ignores pouvaient
donc changer entierement sans invalider l'apercu. Elle utilise desormais la
serialisation canonique de l'export.

**Et le reste.**

- L'option des indices eteinte, `ApplyCellFonts` preparait encore texte, police et taille pour ce que personne ne voit. Le chemin de style le respectait deja ; celui-la non.
- Le resume du README gardait la cause refutee de la 1.6.28. Il raconte maintenant l'histoire, pas l'erreur.
- Tests : 1 753 a 1 774.

## 1.6.30

**Une seule memoire de refus, pour toutes les regions que le moteur nous
prete.** Le releve du 31/08/2026 sur la 1.6.29 est le premier a compter PAR
OPERATION, et ce qu'il montre est net :

```
styleCause SetFont count=4920
styleCause step    count=450    (SetColorTexture)
styleCause SetText count=231    (un par visuel : la memoire tenait)
styleContext lock=0 / ChallengeMode,Map,Chat  count=5571
```

L'indice de clic, protege la veille, ne comptait plus **qu'un refus par
visuel**. La police et les couleurs n'avaient aucune memoire : elles
repartaient a chaque passe, sur des regions dont le client avait deja dit non.

- La memoire etait posee defaut par defaut : d'abord le niveau de cadre, puis l'etat de la souris, puis l'indice -- chacune avec sa variable. Corriger region par region faisait reapparaitre le motif ailleurs a chaque fois. **Une seule regle desormais** : une region dont le client refuse UNE operation n'est plus touchee, et la memoire vit sur une table a nous.
- **Deux refus qui se ressemblent n'appellent pas la meme reponse.** Sous verrou de combat, c'est peut-etre le combat qui refuse : on pose un report et on rejouera a la fin, sans condamner la region. Hors verrou, le combat n'y est pour rien -- les 5 571 refus portaient tous « lock=0 », donc les rejouer ne pouvait rien donner. C'etaient les 450 reports de cette session.
- Tests : 1 742 a 1 753.

Le compteur par operation, pose la veille, aura donc servi exactement a ca :
distinguer ce qui etait corrige de ce qui ne l'etait pas. Sans lui, 5 601 refus
se seraient lus comme un seul probleme.

## 1.6.29

**Ce que la 1.6.28 annoncait comme cause etait faux.** L'audit externe l'a
demontre, et la demonstration se rejoue dans la suite.

`luaL_argerror` n'ecrit « calling X on bad self » que pour un appel de la forme
`objet:Methode()`. Par `pcall(f, objet, ...)`, le meme refus du **meme
receveur** s'ecrit « bad argument #1 ». Les deux messages disent donc la meme
chose : **la region est interdite**. Le message avait change parce que l'appel
etait passe par `tryCall` en 1.6.26, pas parce que la valeur etait en cause.

**La vraie cause des 846 refus : la memoire du refus etait posee SUR la region
interdite.** Ecrire `hint.textRefused = true` sur un objet que le client refuse
est refuse aussi. Le drapeau n'etait donc jamais pose et chaque passe
recommencait. Il vit desormais sur le visuel, une table qui nous appartient.

On ne LIT pas une valeur sur un objet que le client peut interdire ; on n'y
ECRIT pas non plus, pas meme un champ Lua a nous.

**Un import pouvait ecrire dans un profil que son apercu n'avait jamais
decrit.** Comparer le texte protegeait d'une edition du texte, pas d'un
changement de profil entre l'analyse et la confirmation -- ni d'un reglage
modifie entre-temps, absent de l'apercu parce qu'il etait alors identique.
L'analyse retient l'empreinte de sa cible et de tous les champs qu'elle
ecrirait, verifiee au moment d'ecrire. Et l'apercu nomme le profil qui recevra.

**« 846 refus » ne disait pas 846 fois quoi.** Le compteur additionnait des
refus de natures differentes et ne gardait qu'une cause -- la premiere. Une
seconde table, **bornee a huit**, compte par operation et retient un exemple de
chacune. Ce qui ne rentre pas est annonce, pas taise.

**Et le reste.**

- L'option des indices eteinte, plus rien n'est prepare : ecrire un texte, calculer une police et redimensionner une plaque invisibles coutait une exposition aux refus pour un resultat que personne ne voit.
- **Six appels proteges jetaient leur retour** -- la police des cases et les cinq reglages du bouton du moteur. Un appel protege dont personne ne lit le resultat prouve seulement qu'il n'a pas fait tomber l'addon. Le controle statique ne connaissait que le mot `pcall` et laissait passer `tryCall` : il voit les deux.
- Tests : 1 723 a 1 742.

## 1.6.28

**La valeur venait du moteur, pas la region.** Releve en jeu le 31/08/2026,
premiere session ou ces refus etaient comptes :

```
styleFailures=846 styleSteps=3861
styleError=bad argument #1 to '?' (Attempt to access forbidden object
           from code tainted by an AddOn - Usage: self:SetText([text]))
styleContext lock=0 / ChallengeMode,Map,Chat count=801
```

- **« bad argument #1 », pas « bad self ».** Ce n'est pas la region qui est refusee, c'est la VALEUR qu'on lui passe. Elle venait du repli `GetText` de `ApplyCellFonts`, ecrit en 1.6.24 : on relisait le texte sur la region du moteur et on le lui rendait. Proteger la lecture ne servait a rien -- elle reussissait ; c'est la valeur qui etait empoisonnee.
- Le texte de l'indice se lit desormais sur **notre** plaque, jamais sur la region du moteur. Et rien d'autre qu'une chaine ne descend jusqu'a `SetText`, quel que soit l'appelant.
- **Le compteur pose la veille a fait son travail des sa premiere session.** Ces refus etaient la depuis la 1.6.24 et n'apparaissaient nulle part : le `pcall` de l'etape reussit quand l'erreur est interceptee plus bas. C'est precisement ce que la 1.6.27 a corrige, et ce qu'elle a revele.
- Tests : 1 717 a 1 723.

Une reserve sur les chiffres : `styleError` ne retient que la PREMIERE cause.
Les 846 refus ne sont donc pas prouves identiques ; seule la premiere porte
cette signature.

## 1.6.27

**Audit externe de la 1.6.26.** Huit constats, tous verifies dans le code avant
correction.

**Un import pouvait ecrire un profil que le joueur n'avait plus sous les yeux.**
Modifier le texte colle n'invalidait pas l'analyse : coller un export a 22 px,
analyser, corriger le texte a 40, appliquer -- l'addon posait 22. Une
confirmation ne vaut desormais que pour le texte sur lequel elle a ete donnee,
et ce texte est compare une seconde fois au moment d'ecrire, pour le cas ou une
saisie n'emettrait pas l'evenement attendu.

**Une region refusee par le client est abandonnee EN ENTIER.** Retenir le refus
du texte ne suffisait pas : le placement et l'affichage de la meme region
repartaient a chaque passe et se faisaient refuser a chaque passe. C'est le
motif des six cent quatre-vingt-dix, sur les operations voisines de celle qu'on
venait de corriger. Quatrieme fois qu'il se paie.

**Un refus absorbe laissait un diagnostic parfaitement sain.** Le `pcall` de
l'etape REUSSIT quand l'erreur est interceptee plus bas : l'indice disparaissait
sans qu'aucun compteur ne bouge. C'est exactement ce qui a laisse le refus du
31/08 dormir dans le grabber pendant que le rapport annoncait zero. Il est
compte, avec sa cause et son contexte.

**Le diagnostic de recharge se trompait deux fois.**
`error = applied and nil or tostring(failure)` rendait la CHAINE « nil » sur un
succes -- en Lua, `x and nil` retombe toujours sur le `or`. Et sur un refus, la
vraie cause etait ecrite puis immediatement ecrasee par « no duration », alors
qu'une duree existait : c'est son application qui avait ete refusee. Le rapport
designait l'absence de donnee la ou le client avait dit non.

**Et le reste.**

- Verrouiller puis deverrouiller la grille dans le MEME combat laissait un report que rien n'effacait, annonce aux combats suivants. Un report devenu sans objet s'acquitte.
- Le motif « pas pendant un combat » de l'import survivait a une analyse invalide et a une reouverture de la fenetre. Quatre chemins remettaient l'import a zero, chacun a sa facon ; il n'y en a plus qu'un.
- L'assistant de premiere installation restait a 600 x 470 pendant que les cinq autres fenetres se reduisaient : il vit dans un autre fichier et n'avait aucun moyen d'entrer dans la mise a l'echelle commune. Elle lui est ouverte.
- L'infobulle des indices de clic annoncait encore « G, D ou C », le systeme fixe d'avant la 1.6.18. Elle decrit les combinaisons, les initiales de modificateurs et le repli sur le numero.
- **L'assistant etait exempte du controle de couverture** comme « sans logique a verifier ». Il en a. Il est charge et teste, et l'exemption tombe -- au passage, le controle ne reconnaissait qu'une des deux facons de charger un fichier, et aurait donc accuse un fichier reellement execute.
- Tests : 1 680 a 1 717.

## 1.6.26

**`SetText` partait nu.** Releve en jeu le 31/08/2026 :
`Frames.lua:186 calling 'SetText' on bad self (Attempt to access forbidden
object from code tainted by an AddOn)`.

- C'etait le **seul appel non protege** de `ApplyClickHint`, ecrit en 1.6.24. Tous ses voisins passent par `tryCall` ; celui-la partait sans garde-fou, sur une `FontString` que le moteur d'auras peut declarer interdite.
- Il emportait son appelant. Depuis `ApplyCellFonts`, cela veut dire `LayoutButtons`, dont le drapeau d'attente n'est efface qu'a sa derniere ligne : la plaque « en attente » se serait rallumee a chaque combat du reste de la session. C'est le defaut de police de la 1.5.35, revenu a l'endroit exact ou il avait ete corrige ailleurs.
- La pose de l'indice etait de surcroit **hors du decoupage en etapes** de `StyleAuraVisual`, qui existe precisement pour qu'un refus n'emporte pas les huit autres etapes du visuel. Elle y rentre.
- Le refus est retenu, comme ceux du niveau de cadre et de l'etat de la souris : l'objet ne redevient jamais accessible, et le rejouer a chaque passe est ce qui a produit six cent quatre-vingt-dix refus par cle, trois fois de suite.
- Lire le texte est protege aussi : lire un objet interdit leve autant qu'y ecrire.
- Tests : 1 671 a 1 680.

**Le releve de la meme session est par ailleurs le plus propre a ce jour :**
zero refus de style, zero `pendingAuraStyle`, aucun evenement refuse, 246/246
emplacements, 138/138 sons. Les six cent quatre-vingt-dix refus par cle
mythique, corriges en trois fois de la 1.6.16 a la 1.6.21, ne se produisent
plus.

## 1.6.25

**Revue d'interface.** Quatre defauts mesures, dont deux que la 1.6.24 venait
d'introduire.

**L'indice de clic ne disparait plus.** La 1.6.24 avait raison de refuser
qu'une combinaison longue deborde sur la case voisine, et tort de ne rien
dessiner a la place : cette lettre est le SEUL reperage de la dissipation qui
ne passe pas par la couleur. Et la couleur ne suffit pas -- les trois couleurs
de clic partagent leur teinte avec trois couleurs de type, a moins de quinze
degres : rouge avec Bleed (0 degre), bleu avec Magic (9,5), orange avec Disease
(13,1). Quand la combinaison complete ne tient pas, la case affiche desormais
le NUMERO de la dissipation, qui tient toujours sur un caractere et ne se
confond avec aucun indice de bouton -- ceux-ci s'ecrivent G, D, M, 4 et 5.

**Les titres de section rendaient 3,95:1.** Le token etait pose en blanc a 41 %
d'opacite : sa couleur reelle est sa composition sur le panneau, et personne ne
la mesurait. 45 % donne 4,53:1, au-dessus des 4,5 qu'un texte de moins de
18 px demande. Un controle statique calcule maintenant les trois tokens de
texte a chaque execution.

**Un nom de profil rogne redevient lisible.** La 1.6.24 avait borne le libelle
des boutons de lieu pour qu'il ne deborde plus, sans donner nulle part ou lire
le nom complet. L'infobulle le porte, et se relit a chaque survol puisque ce
nom change.

**Sept controles poses depuis la 1.6.20 ignoraient la convention d'aide du
fichier**, dont deux boutons qui ne portent qu'un chevron. Le fichier attache
pourtant une aide a vingt autres controles.

**Et le reste.**

- Le champ de nom sert a creer ET a renommer ; son texte d'invite disparait a la premiere lettre, et plus rien ne le nommait. Il porte un libelle visible.
- Les deux lignes de la section des lieux etaient hautes d'une ligne et portaient une explication de deux. L'explication passe en infobulle, la ligne dit l'essentiel.
- **Neuvieme mensonge du bouchon :** `HookScript` ne faisait RIEN. Les vingt infobulles de l'addon etaient posees dans le vide aux yeux des tests, et un bouton sans aide rendait exactement la meme chose qu'un bouton avec.
- Tests : 1 637 a 1 671.

Deux constats de la revue sont ecartes, avec leur raison. La poignee de
deplacement fait 24 x 14 px, sous la base de 24 x 24 : l'exception d'espacement
s'applique, rien ne se trouve a moins de 24 px d'elle. Et les deux cents
pixels vides du gestionnaire de profils quand la liste est courte demanderaient
de repositionner la fenetre a chaque rafraichissement, ce qui coute plus que ce
que ca rend.

## 1.6.24

**Corrections de l'audit externe de la 1.6.23.** Aucun defaut du coeur : ce
sont les valeurs extremes que le reglage autorise deja, et les etats
transitoires de l'interface.

**Deux debordements, tous deux mesures.**

- La plaque de l'indice de clic grandissait avec le nombre de caracteres **sans jamais regarder la cellule** : 31,46 px sur une case de 22 px pour « ALT-CTRL-SHIFT-2 », donc du texte pose sur la case voisine. Toutes ces combinaisons sont valides ; le test qui la gardait ne connaissait que les trois gestes par defaut. La plaque et la police se reduisent maintenant **ensemble** jusqu'a tenir, et sous la taille minimale l'indice n'est pas dessine du tout -- une bouillie illisible vaut moins que rien, et l'infobulle nomme deja le geste. Le nouveau test parcourt les **1 160** combinaisons possibles, a toutes les tailles de cellule.
- Un nom de profil peut faire trente-deux octets ; les boutons de lieu faisaient cent douze pixels de large et leur libelle n'avait ni largeur ni limite de ligne. Ils passent en deux colonnes de 232 px, avec un libelle borne qui rogne au lieu de deborder sur le bouton voisin.

**Trois surfaces ne se reveillaient pas a l'entree en combat**, le seul moment
ou leur verdict change tout seul, et celui ou une interface qui ment coute le
plus cher.

- La poignee de deplacement recoit desormais la meme surcharge de combat que la couche de recharge : avec « afficher seulement en combat », les cases apparaissaient au pull et elle restait cachee.
- La fenetre de remappage garde des boutons actifs si elle est ouverte avant le pull. Les donnees etaient sures -- la logique refuse avant toute ecriture -- mais l'interface promettait une action qui ne finissait qu'en refus.
- Le motif « pas pendant un combat » de l'import s'affichait meme sans apercu applicable, donc sans bouton a expliquer.

**Et le reste.**

- Au-dela de six profils, la fenetre renvoyait aux commandes texte : un cul-de-sac dans une fonction presentee comme graphique. Les six rangees se recyclent, avec une pagination bornee au rafraichissement -- supprimer le dernier profil d'une page laissait sinon la liste sur une page vide.
- `CONTROL_COLOR` etait la seule globale Lua non necessaire de l'addon. Elle est locale.
- Le report de la poignee etait inscrit **a chaque pull** pour une valeur qui n'avait pas bouge. Troisieme fois que ce motif se paie, apres le niveau de cadre et l'etat de la souris.
- La liste des changements du README s'arretait a la 1.6.19. Elle couvre les cinq versions suivantes.
- **Huitieme mensonge du bouchon :** `SetWordWrap` n'etait pas retenu, donc un libelle qui rogne et un libelle qui deborde rendaient la meme chose.
- Tests : 1 597 a 1 637.

## 1.6.23

**La fenetre des profils ne repondait a rien sur une base vide.** Signale en
jeu le 30/08/2026.

- Le fond de la saisie du nom etait **plus sombre que le panneau**, et la case etait vide : elle etait donc litteralement invisible. Le texte d'a cote disait « saisissez un nom ci-dessus » en montrant du vide. Et comme tout le reste de la fenetre attend qu'un profil existe, le seul controle capable d'en creer un etait le seul qu'on ne voyait pas. Fond clair, cadre, et un texte d'invite qui s'efface a la premiere lettre -- le meme motif que la zone de recherche.
- Les quatre boutons de lieu etaient grises **sans un mot d'explication**, ce qui ne se distingue pas d'une fenetre en panne. Ils disent maintenant pourquoi : une surcharge designe un profil nomme, elle n'en contient pas.
- Un bouton dit ce que le PROCHAIN clic fera. « Deverrouiller les lieux » ne disait donc pas, lu seul, que les lieux etaient verrouilles. La fenetre l'ecrit.
- **Septieme mensonge du bouchon de test :** `SetText` ne declenchait pas `OnTextChanged`. En jeu il le declenche. Une case dont l'invite ne s'efface qu'a cet evenement passait donc pour reglee sans l'etre.
- Tests : 1 584 a 1 597.

## 1.6.22

**La poignee « C » restait seule a l'ecran quand la grille etait masquee.**
Signale en raid le 30/08/2026.

- Elle ne suivait que le verrou et l'etat active. « Afficher en raid » eteint, les cases disparaissaient et la poignee restait -- une lettre posee sur rien. La regle « afficher seulement en combat » donnait le meme resultat.
- Elle pose maintenant exactement la meme question que les cases. C'est le quatrieme consommateur de ce verdict apres le pilote securise, le registre sonore et la couche de recharge, et la raison ne change pas : une couche non protegee qui decide seule finit par contredire la grille.
- L'apercu et la fenetre de reglages forcent deja ce verdict a vrai : la poignee reste donc attrapable exactement quand on place la grille, y compris la ou le contexte la masque.
- Tests : 1 577 a 1 584.

## 1.6.21

**Le refus des 690 n'avait pas diminue : il avait change d'appel.**

Releve d'une seconde cle mythique, le 30/08/2026, sur la 1.6.20 :
`style failures=690 steps=6210`, exactement le meme chiffre que la clé
precedente -- mais l'erreur nommait cette fois `SetMouseMotionEnabled`, la
1.6.16 ayant traite `SetFrameLevel`.

- La correction precedente portait sur **l'appel** qui echouait, pas sur le **motif** : reposer une valeur inchangee, a chaque passe, sur un objet qui appartient au moteur d'auras. Le niveau de cadre corrige, l'appel suivant de la meme fonction a simplement repris le compte, a l'identique.
- L'etat de la souris suit donc le meme traitement : il n'est pose que s'il a change, et un refus deja constate n'est plus retente. La memoire ne coute rien -- l'appel n'a jamais eu d'effet sur cet objet, donc l'etat de la souris n'y suivait deja pas l'option d'infobulle.
- Le releve de la meme cle est par ailleurs sain : 82 boutons prets, 246/246 emplacements, 138/138 sons enregistres, 0 relance, 0 unite sautee, aucun evenement refuse. `lock=0` sur les 690 : aucun verrou de restriction, de la contamination ordinaire.
- Tests : 1 574 a 1 577.

## 1.6.20

**Ce qu'un combat doit refuser, il doit le refuser en entier.** Quatre
operations ecrivaient d'abord et decouvraient ensuite que le combat leur
interdisait la suite.

- **Remapper un clic** ecrivait le profil, rafraichissait les textes et repondait « c'est fait », pendant que la pose des attributs securises etait reportee a la fin du combat. Le joueur voyait la nouvelle combinaison et l'ancienne lancait encore le sort. Refuse avant la premiere ecriture.
- **Appliquer un import** n'avait aucune garde. Un profil porte les clics, la taille, la disposition et la visibilite d'un seul coup : en combat, une partie etait differee et l'autre non, et l'addon annoncait quand meme « Profil importe ». Lire et verifier restent permis ; le bouton Appliquer se grise, avec la raison a cote, et se rallume a la fin du combat sans qu'on ait a recoller le texte.
- **Verrouiller les lieux** posait le drapeau, puis le rechargement refusait en silence. L'etiquette cessait alors de nommer le profil dans lequel les reglages continuaient d'ecrire. Refuse en entier, et la commande imprime le vrai resultat au lieu d'annoncer le nouvel etat quoi qu'il arrive.
- **Renommer un profil** ne suivait que les affectations. Les surcharges de lieu gardaient l'ancien nom : un pointeur mort, donc un profil que l'addon annoncait sans jamais le charger. Supprimer les parcourait deja ; les deux passent maintenant par le meme balayage.

**Le geste affiche est le geste pose, partout.** Les cases lisaient la
combinaison reelle depuis la 1.6.18. Les deux apercus, la page Dissipations,
l'infobulle et `/cleansive spells` traduisaient encore le NUMERO du clic avec
leur propre table : apres un remappage, la case disait une chose et la page une
autre. Une seule description les alimente desormais tous.

- L'indice court se **construit** au lieu de se chercher dans une table : l'initiale de chaque modificateur, puis la lettre du bouton. La table ne couvrait que les combinaisons qu'on avait pensees, donnait la meme lettre a Ctrl + 1 et Ctrl + 2 -- deux dissipations, un seul indice -- et rien du tout a une combinaison a deux modificateurs. La plaque sombre derriere l'indice suit sa longueur.
- La legende des couleurs de la page Dissipations nommait les trois gestes d'origine, ecrits en dur dans les deux langues.

**Deux fonctions livrees sans ecran le sont maintenant avec.**

- **Regler les clics**, sur la page Dissipations : chaque rangee ecoute le geste que vous pressez, modificateurs compris. C'est le meme chemin que le clic reel, donc ce qu'elle capture est exactement ce qui partira. Un bouton remet les trois gestes d'origine, ensemble -- les reecrire un par un buterait sur un conflit passager.
- **Les surcharges par lieu et leur verrou**, dans le gestionnaire de profils : un bouton par lieu, qui fait le tour des profils. Elles n'existaient que par `/cleansive profile env`, donc pour qui avait lu le journal des versions.

**Le gestionnaire de profils dit lequel des deux profils il nomme.** Son
etiquette tenait compte du lieu, son chevron et ses boutons non. Choisir un
profil habituel pendant qu'une surcharge de lieu gagnait repondait « il est
maintenant utilise » alors qu'il n'etait pas charge. Deux lignes : le profil
charge ici, le profil habituel de la specialisation -- et le message dit quand
la surcharge garde la main.

**La page Aide annoncait toutes les commandes et en oubliait onze.** Le test
qui surveillait cette promesse portait la liste des commandes **ecrite a la
main** : il a vieilli exactement comme la page. La liste se derive maintenant
de `Core.lua`, et le controle a trouve trois oublis de plus que l'audit.

- Le README decrit les trois gestes comme des defauts, ce qu'ils sont depuis la 1.6.18, et documente `clicks`, `profile env` et `profile lock`.
- `ApplySecureBindings` construisait une table par case -- quatre-vingt-deux par pose -- que personne ne lisait.
- **Deux tests ne pouvaient rien voir.** Le detecteur de chevauchements prend une PHOTO des enfants : les deux fenetres ouvertes apres cette ligne etaient parcourues, et vides. Et le bouchon ignorait `RegisterForClicks`, donc un bouton qui n'entend que le clic gauche et un bouton qui entend les cinq rendaient la meme chose.
- Tests : 1 513 a 1 574.

## 1.6.19

**Apres un clic remappe, la case pouvait afficher la mauvaise recharge.**
Confirme en jeu.

- Le registre interne deduisait le sort d'une liste ecrite en dur : gauche, droite, Ctrl + gauche, bouton 4. Depuis que les combinaisons se reglent (1.6.18), cette liste decrivait des gestes que le joueur avait peut-etre deplaces. Le clic securise partait correctement -- c'est le jeu qui l'execute -- mais le releve nommait un autre sort, donc la case affichait sa recharge, ou aucune.
- Le geste est desormais traduit par la **carte effective**, celle-la meme qui pose les attributs securises, miroir du bouton de pouce compris. Une seule source : le clic et le releve ne peuvent plus diverger. C'est le point 42 de l'inventaire, « rapprocher apercu, infobulle et clic reel d'un pipeline commun », applique la ou ca comptait le plus.
- Un geste qui n'appartient a aucune dissipation n'inscrit plus rien, au lieu de retomber sur la premiere.
- **Le harnais cablait les trois modificateurs sur « relache ».** Tout code qui en lit un passait pour verifie sans l'etre -- c'est exactement ce qui a laisse ce defaut sortir. Ils sont pilotables, et le test rejoue le remappage comme en jeu.
- Tests : 1 504 a 1 513.

## 1.6.18

**Remappage des clics de dissipation**, avec ce qui le rend acceptable : la
detection des conflits.

- Chaque dissipation peut aller sur n'importe quel bouton de souris de 1 a 5, avec Alt, Ctrl et Maj. `/cleansive clicks` liste les trois clics, leur combinaison et le sort qui s'y trouve ; `/cleansive clicks 3 SHIFT-2` en deplace un.
- **Le controle des conflits est la fonction principale, le remappage n'en est que la consequence.** Le point 305 de l'inventaire interdit « le remappage libre sans controle des conflits », et il a raison : deux dissipations sur la meme combinaison, ce n'est pas un reglage exotique, c'est un clic qui ne fera pas ce qu'il annonce en plein combat. Rien n'est ecrit tant qu'un conflit existe, et le refus nomme ce qui bloque.
- Les deux gestes que l'addon se reserve -- clic milieu pour cibler, Ctrl + milieu pour focaliser -- sont refuses comme destination.
- **Un defaut trouve par son propre test :** deplacer une dissipation laissait l'ANCIENNE combinaison armee. Ctrl + gauche continuait de lancer le sort apres son depart vers Maj + droit : deux combinaisons pour une dissipation, dont une que le joueur croyait avoir liberee. Ce qui n'est plus pose est desormais desarme.
- La lettre affichee sur la case suit la combinaison reelle. Elle se deduisait du NUMERO du clic, ce qui ne veut plus rien dire des qu'on peut le deplacer.
- Les miroirs des boutons de pouce cedent au reglage : si vous prenez le bouton 4, c'est votre choix qui gagne.
- Un remappage se transfere avec le profil, et une liste illisible ou en conflit avec elle-meme est refusee ENTIERE -- en accepter la moitie donnerait un jeu de clics que personne n'a choisi.
- Tests : 1 474 a 1 504.

## 1.6.17

**Surcharges de profil par lieu.** Monde ouvert, donjon, raid, JcJ.

- C'est la plus petite surcharge qui puisse exister : elle **ne porte aucun reglage**, elle designe seulement un profil nomme deja existant pour un lieu donne. Rien de neuf a comprendre, rien qui bascule sans qu'on l'ait demande lieu par lieu — le point 304 de l'inventaire interdit « une multitude de profils automatiques incomprehensibles », et c'est une bonne interdiction.
- **Un verrou global** fige tout : la grille ne change plus quand vous traversez une porte, quoi qu'il arrive. `/cleansive profile lock`.
- Le lieu fait desormais partie de l'identite du profil actif. Sans cela, entrer en donjon ne rechargeait rien : le personnage et la specialisation n'avaient pas bouge, et la surcharge n'aurait jamais servi a rien.
- Le libelle du profil actif annonce le lieu quand une surcharge s'applique. Verrouille, il ne promet plus un lieu qui n'agit pas.
- `/cleansive profile env <world|dungeon|raid|pvp> [nom]` — sans nom, la surcharge est retiree. Le verbe et son contraire sur la meme ligne.
- **Un defaut trouve par son propre test :** supprimer un profil actif **par surcharge** ne rechargeait rien. La verification portait sur le chemin -- l'affectation nommee -- et pas sur l'identite. C'est desormais `self.db == la table supprimee` qui decide, ce qui couvre les deux chemins. Les surcharges mortes sont nettoyees comme les affectations mortes, pour la meme raison : un pointeur laisse en place ressusciterait au premier profil qui reprendrait ce nom.
- Tests : 1 453 a 1 474.

## 1.6.16

Premiere tranche du chantier « sortir les elements visuels du cadre protege ».
Elle est plus petite que prevu, parce que le code a repondu une chose que je ne
savais pas.

- **Nos propres cadres poses SOUS l'objet du moteur ne sont jamais refuses.** Seul l'objet du moteur lui-meme l'est. Deplacer les decorations n'etait donc pas le sujet : le sujet etait l'unique appel qui touche cet objet.
- **Le niveau du bouton du moteur n'est repose que s'il a change**, c'est-a-dire presque jamais -- il ne depend que de la priorite du type. Il etait pourtant repose a chaque passe de style. C'est cela qui a transforme un refus en **690 refus sur une seule cle**. Sur la prochaine, ce nombre doit tomber a un par visuel, puis a zero.
- **Nos deux couches suivent le niveau REEL du bouton, plus celui qu'on avait demande.** Quand le client refuse, le bouton garde son ancien niveau : le voile de duree et la couche des libelles se retrouvaient places par rapport a une valeur qui n'existait pas. On lui demande maintenant le niveau qu'il a.
- **Le harnais ne mesurait aucun empilement** : `SetFrameLevel` tombait dans le bouchon generique et `GetFrameLevel` rendait toujours 1. Toute la superposition de l'addon etait invisible aux tests. Elle est mesuree.
- Tests : 1 449 a 1 453.

## 1.6.15

Corrections issues d'un audit externe de la 1.6.14.

- **La migration des noms contenant une barre verticale ne s'executait pas chez ceux qui en avaient besoin.** Ajoutee en 1.6.12, elle etait placee sous un marqueur que la **1.6.11 posait deja**, sans rien migrer. Toute personne passee par la 1.6.11 -- c'est-a-dire exactement la population concernee -- ne la voyait jamais. Un marqueur qui decrit un autre nettoyage ne peut pas servir de marqueur de migration : celui-ci lui est propre. Et mon test forcait ce marqueur a rien, donc il verifiait une installation qui SAUTE la 1.6.11. Il modelise maintenant une vraie base issue d'une session 1.6.11.
- **Un suffixe de collision pouvait rendre un profil introuvable.** « nom de 32 octets » suivi de « (2) » fait 36 : la cle etait bien enregistree, et toute recherche ulterieure la cherchait a 32. La place du suffixe est desormais reservee avant la coupe, qui reste sure en UTF-8.
- **La molette sautait la moitie d'une page.** Le gestionnaire du modele Blizzard deplace deja de son pas -- ou, a defaut, de la moitie de la hauteur visible. La 1.6.13 l'appelait puis ajoutait 40 px : environ 300 px par cran. Un seul pilote a la fois, et le meme pas de 40 px des deux cotes. Le bouchon ne deplacait rien, donc rien ne pouvait le voir : il deplace maintenant.
- **Le gestionnaire de profils suit l'entree en combat.** Il savait griser ses boutons, mais rien ne l'appelait au pull : ouvert avant, il gardait des boutons actifs qui repondaient ensuite par un refus.
- **Une seule cle d'import rejetee pouvait remplir la fenetre.** Leur nombre etait borne, pas leur longueur.
- **L'etat de la souris n'est plus abandonne avec le niveau de cadre.** Les deux vivaient dans la meme etape : la levee du premier sautait le second, puis le refus retenu sautait les deux pour toujours, et l'option d'infobulle ne s'appliquait plus jamais aux boutons d'aura.
- **Je ne verifiais que mon archive locale, jamais celle que les joueurs telechargent.** Sur celle de la CI, mon propre controle d'archive echouait : elle sort en CRLF alors que le depot est en LF. J'ai d'abord cru a un `.gitattributes` manquant. Verifie sur l'archive publiee de la v1.6.15 : **ca ne vient pas de git, c'est l'empaqueteur BigWigs qui convertit**, et c'est la convention des addons WoW depuis toujours. Le controle ne refuse donc plus le CRLF que dans le DEPOT. Le `.gitattributes` reste, pour les diffs.
- Tests : 1 437 a 1 449.

## 1.6.14

**Premier releve d'une vraie cle mythique**, le 30/08/2026. Il repond aux deux
questions que deux audits laissaient ouvertes.

- **Le registre sonore natif tient sous restriction.** `sound registered=230/230` puis `92/92`, `retries=0`, aucun refus, pendant toute une cle avec `ChallengeMode` actif. `AddAuraSound` n'est donc PAS refuse dans ce contexte : la garde que les audits recommandaient aurait coupe les alertes d'une cle entiere pour un risque qui ne se realise pas. Elle n'est pas ajoutee, et ce n'est plus une supposition.
- **Le niveau de cadre du moteur, lui, est bien refuse -- 690 fois en une cle.** `style failures=690 steps=6210` : neuf etapes par passe, **une seule** echoue. Le voile, la bande de type, les charges et la lettre de clic s'appliquaient donc correctement ; seul `SetFrameLevel` etait refuse, avec « Attempt to access forbidden object from code tainted by an AddOn », et toujours avec `lock=0` -- l'addon se croyait libre.
- Les deux garde-fous en place n'ont rien vu : `IsForbidden` repond que l'objet n'est pas **declare** interdit, et `CheckAllowProtectedFunctions` a accorde la permission. **Le seul temoin fiable est l'echec lui-meme.** Il est desormais retenu, pour cette etape seule, et n'est plus retente : 690 echecs, c'etait 690 relances inutiles. Les huit autres etapes continuent de s'appliquer -- abandonner tout le visuel aurait coute bien plus que le niveau de cadre.
- La memoire meurt avec le visuel : une reconstruction du moteur redonne sa chance a l'objet suivant.
- Tests : 1 433 a 1 437.

L'historique complet est dans `CHANGELOG.md`, livre avec l'addon.
