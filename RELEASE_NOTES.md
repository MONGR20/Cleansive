# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

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
