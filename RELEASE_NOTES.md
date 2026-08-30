# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

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

## 1.6.13

**Le defilement des pages de reglages ne fonctionnait pas en jeu.** Signale sur
captures, sur la 1.6.12 publiee.

- **La cause est une ligne de la 1.6.7.** Les deux scripts de la zone de defilement etaient poses avec `SetScript`, qui **remplace**. `UIPanelScrollFrameTemplate` met les siens sur ces memes evenements pour piloter sa barre : ses bornes, son curseur, sa visibilite. En les ecrasant, la barre n'etait plus jamais configuree — et la molette du modele, qui s'appuie dessus, ne deplacait plus rien. Les gestionnaires sont desormais **chaines** : celui du modele d'abord, le notre ensuite. Et une molette a nous, qui ne depend d'aucun heritage, deplace de 40 px en restant dans les bornes.
- **Le harnais ne pouvait pas le voir, et c'est le vrai defaut.** Le bouchon ignorait qu'un modele Blizzard arrive AVEC ses scripts deja poses : ecraser l'un d'eux y passait pour anodin. Il le modelise maintenant, et un test verifie que le gestionnaire du modele est encore appele apres les notres.
- **La bande « la page continue plus bas » recouvrait la derniere ligne** de chaque page longue. Elle etait posee dans la zone de lecture ; celle-ci s'arrete maintenant 22 px au-dessus d'elle. La hauteur reellement visible passe donc de 550 a 528 px, et les pages qui la depassent defilent — ce qu'elles sont censees faire.
- **Le rapport de diagnostic affichait « lock=0 » puis « one » sur deux lignes.** Le separateur des restrictions etait une barre verticale : dans un texte affiche par WoW, « | » ouvre une sequence d'echappement, et « |none » se lit « |n » -- un retour a la ligne -- suivi de « one ». Le separateur est desormais une barre oblique, et un test refuse toute barre verticale dans ce releve.
- Tests : 1 417 a 1 433.

L'historique complet est dans `CHANGELOG.md`, livre avec l'addon.
