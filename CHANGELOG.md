# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

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

## 1.6.13

**Le defilement des pages de reglages ne fonctionnait pas en jeu.** Signale sur
captures, sur la 1.6.12 publiee.

- **La cause est une ligne de la 1.6.7.** Les deux scripts de la zone de defilement etaient poses avec `SetScript`, qui **remplace**. `UIPanelScrollFrameTemplate` met les siens sur ces memes evenements pour piloter sa barre : ses bornes, son curseur, sa visibilite. En les ecrasant, la barre n'etait plus jamais configuree — et la molette du modele, qui s'appuie dessus, ne deplacait plus rien. Les gestionnaires sont desormais **chaines** : celui du modele d'abord, le notre ensuite. Et une molette a nous, qui ne depend d'aucun heritage, deplace de 40 px en restant dans les bornes.
- **Le harnais ne pouvait pas le voir, et c'est le vrai defaut.** Le bouchon ignorait qu'un modele Blizzard arrive AVEC ses scripts deja poses : ecraser l'un d'eux y passait pour anodin. Il le modelise maintenant, et un test verifie que le gestionnaire du modele est encore appele apres les notres.
- **La bande « la page continue plus bas » recouvrait la derniere ligne** de chaque page longue. Elle etait posee dans la zone de lecture ; celle-ci s'arrete maintenant 22 px au-dessus d'elle. La hauteur reellement visible passe donc de 550 a 528 px, et les pages qui la depassent defilent — ce qu'elles sont censees faire.
- **Le rapport de diagnostic affichait « lock=0 » puis « one » sur deux lignes.** Le separateur des restrictions etait une barre verticale : dans un texte affiche par WoW, « | » ouvre une sequence d'echappement, et « |none » se lit « |n » -- un retour a la ligne -- suivi de « one ». Le separateur est desormais une barre oblique, et un test refuse toute barre verticale dans ce releve.
- Tests : 1 417 a 1 433.

## 1.6.12

**Le changelog de la 1.6.11 annoncait deux corrections qui n'existaient pas.**

Mon script d'edition ecrivait le fichier APRES ses trois remplacements. Le
troisieme est tombe sur une ancre absente, ce qui a annule les deux premiers --
qui avaient deja affiche « ok ». J'ai cru ces « ok » et je les ai recopies dans
le changelog. Un audit externe l'a vu ; aucun de mes 1 397 tests ne le pouvait,
puisque les deux corrections etaient invisibles a la suite.

L'outil ecrit desormais apres CHAQUE remplacement et relit le fichier sur disque
pour confirmer. Les deux corrections sont faites, et testees :

- **Au-dela de six profils, l'avertissement se pose sous la liste.** Il reutilisait le texte de la liste vide, ancre a la place de la premiere rangee : il recouvrait le premier profil, exactement quand la liste est la plus chargee.
- **Les trois boutons qui changent un profil sont grises pendant un combat.** La logique refusait deja, donc la base n'a jamais pu etre abimee -- mais un bouton actif qui repond par un refus est une promesse non tenue.

**Le reste de l'audit :**

- **Les anciens noms de profils contenant une barre verticale sont migres.** Les 1.6.9 et 1.6.10 les acceptaient ; la 1.6.11 la retire des saisies mais laissait les cles enregistrees telles quelles. Un bouton transmettait « Raid|Soins », la normalisation en faisait « RaidSoins », et le profil devenait introuvable : utiliser, renommer et supprimer echouaient tous. La migration renomme la cle ET suit les affectations. En cas de collision, l'ancien est garde sous un suffixe plutot qu'ecrase -- perdre un profil pour cause de doublon serait pire que d'en avoir deux a trier.
- **Le refus de changement de profil n'est plus imprime deux fois.** La garde annoncait le refus ET le rendait a l'appelant, qui l'annoncait a son tour.
- **Ouvrir les reglages en combat ne fait plus apparaitre la couche non protegee seule.** La fenetre ouverte force l'affichage -- mais en combat le pilote securise ne peut pas etre relache. Dans un raid ou la grille est masquee par contexte, un chiffre de recharge se retrouvait au-dessus de rien. Les surcharges ne promettent plus que ce que le pilote peut tenir.
- **L'apercu d'import borne la longueur de chaque valeur, pas seulement le nombre de lignes.** Un seul changement de filtre porte jusqu'a 500 identifiants de chaque cote : la ligne revenait a la ligne autant de fois qu'il fallait et repassait sous les boutons. La liste des rejets est bornee de la meme facon.
- **Toujours ouvert et assume :** `AddAuraSound` sans garde de restriction, et le jeton de revision brut dans un ZIP construit a la main. Le premier demande une cle Mythique+ pour trancher, le second une publication par la chaine CI.
- Tests : 1 397 a 1 417.

## 1.6.11

Corrections issues d'un audit externe de la 1.6.10.

**Les deux defauts serieux etaient dans les profils nommes, arrives en 1.6.9.**

- **Changer de profil pendant un combat est refuse.** `use`, `own` et la suppression modifiaient la base PUIS demandaient un rechargement que le combat refuse : les cles actives restaient a rien pendant que les reglages continuaient d'ecrire dans l'ancien profil, le message annoncant le nouveau. Une seconde operation ecrivait alors sous une cle vide au lieu du personnage. Un changement de profil ne peut pas etre a moitie applique — c'est deja la regle retenue pour l'apercu en 1.6.1. Les boutons concernes sont grises pendant le combat.
- **Un profil partage est desormais reellement charge au demarrage.** La resolution de l'affectation n'existait que dans le chemin de changement de specialisation, qui sort tot quand les cles n'ont pas bouge. Une connexion ou la specialisation est deja connue au chargement annoncait donc le profil partage tout en ecrivant dans le profil propre. Il n'y a plus qu'un seul endroit ou la question se pose.

**Le reste :**

- **La couche non protegee suit enfin les regles solo, groupe et raid.** « Afficher en raid » eteint, elle pouvait laisser un chiffre de recharge, le badge TEST ou la plaque d'attente seuls a l'ecran, sans grille dessous. C'est le troisieme consommateur de ce verdict apres le pilote securise et le registre sonore : il ne se calcule plus qu'a un seul endroit.
- **Cleansive exportait un profil qu'il refusait ensuite d'importer.** Deux ensembles de 500 identifiants depassent l'ancienne borne de 8 000 caracteres. Un test tient maintenant le contrat A LA TAILLE MAXIMALE.
- **Un nom de profil n'est plus coupe au milieu d'un caractere accentue** : la borne comptait des octets. La barre verticale est refusee — elle separe les deux noms du renommage, et dans un texte affiche par WoW elle ouvre une sequence de mise en forme.
- **Les listes de priorite et d'exclusion sont reparees entree par entree.** Une base contenant `priority = { 42 }` faisait lever des le premier roster. Le stockage des profils nommes est nettoye de la meme facon : une cle non textuelle remontait jusqu'au tri, qui leve en comparant un nombre a une chaine.
- **Toute suppression d'alerte native passe par un seul endroit**, donc le compteur des alertes vivantes ne derive plus apres un nettoyage d'orphelin.
- L'apercu d'import est borne a huit lignes suivies d'un compte. Les deux fenetres de profils suivent la mise a l'echelle et se ferment par Echap. Le README documente `/cleansive profile` et `/cleansive sound`.
- **Correction apportee a cette entree par la 1.6.12 :** elle annoncait aussi que l'avertissement au-dela de six profils se posait sous la liste, et que les boutons de profils etaient grises en combat. **Ces deux corrections n'etaient pas dans la 1.6.11** -- un script d'edition les avait annulees en silence. Elles sont faites en 1.6.12.
- **Non corrige, et assume :** `AddAuraSound` est toujours tente sans garde de restriction. Le risque est reel — une cle mythique garde `ChallengeMode` actif alors que `InCombatLockdown` dit non — mais toute garde que je pourrais ecrire ici couperait les alertes pendant une cle entiere dans le cas « afficher seulement en combat ». Cela demande une session en jeu pour trancher, pas une supposition de plus.
- Tests : 1 356 a 1 397.

## 1.6.10

- **Le bouton du son d'alerte est enfin verifie.** Le mecanisme etait teste depuis la 1.6.6 et le bouton pose en 1.6.7, mais rien ne verifiait qu'il etait branche sur quoi que ce soit : le debrancher ne faisait tomber aucun test. Une option qu'on ne peut atteindre que par une commande n'est pas livree. La rotation, le libelle qui suit, et la disparition du reglage quand le son est coupe sont maintenant tenus.
- Le nombre de sons proposes n'est PAS ecrit dans le test : il depend du client. Le figer aurait fait tomber ce test le jour ou la liste change, sans qu'aucun defaut existe.
- Tests : 1 345 a 1 356.

## 1.6.9

**Profils nommes.** Un profil qu'on nomme, et que plusieurs personnages et specialisations peuvent utiliser en meme temps.

- Creer depuis les reglages courants, utiliser, renommer, supprimer — par la fenetre **Profils** (bouton sur la carte de profil, page General) ou par `/cleansive profile`.
- **Deux regles portent tout le reste.** Le profil propre d'une specialisation n'est JAMAIS supprime quand elle pointe vers un profil partage : revenir dessus reste toujours possible, y compris apres la suppression du partage — sinon supprimer un profil partage laisserait des personnages sans rien. Et **rien ne bascule tout seul** : le point 304 de l'inventaire interdit les profils automatiques, et une specialisation ne pointe vers un profil nomme que si on le lui a demande.
- **Supprimer desaffecte tout le monde**, pas seulement le personnage connecte. Un pointeur laisse en place aurait fait repartir un autre personnage sur les valeurs d'origine a sa prochaine connexion, sans que rien ne le dise — et pire, il aurait ressuscite tout seul le jour ou un profil aurait repris le meme nom.
- Un nom vient d'une saisie libre : longueur bornee a 32, espaces de bord rognes, caracteres de controle retires. Un retour a la ligne dans un nom aurait casse la liste et l'export en silence.
- La suppression demande deux clics, comme toute action irreversible de l'addon. La fenetre montre six profils ; au-dela, elle le dit plutot que de laisser croire qu'il n'y en a que six.
- Tests : 1 292 a 1 345. Neuf injections de defaut verifiees, dont deux qui ne tombaient pas au premier essai : elles visaient le bon cas sans l'exercer.

## 1.6.8

**Taille et espacement separes en groupe et en raid.** Quarante cases a la taille d'un groupe de cinq ne tiennent nulle part.

- Nouvelle bascule sur la page Apparence, **eteinte par defaut** : un raid garde alors les valeurs du groupe, exactement comme avant. Activee, il prend sa propre taille de case et son propre espacement. Le changement s'applique en entrant ou en sortant d'un raid — et pendant un combat, a la fin de celui-ci, redimensionner une case etant une modification protegee.
- **L'apercu suit.** Il existe pour regler une grille de raid SANS raid : au-dela de cinq cases simulees, il montre donc la geometrie de raid, sinon il ne sert plus a ce pour quoi il a ete fait.
- **Dix-huit endroits lisaient la taille et l'espacement directement.** Ils passent tous par un seul accesseur : c'est la seule facon que la geometrie ne se decide qu'a un endroit, et c'etait la vraie raison pour laquelle ce chantier etait reporte depuis la 1.6.
- **Les deux curseurs de raid sont grises, jamais caches.** Un controle qui disparait laisse un trou et ne dit plus qu'il existe — et surtout, un controle cache echappe au controle de recouvrement, qui ne mesure que ce qui s'affiche.
- **Un garde-fou ecrit puis retire.** J'avais ajoute une fonction pour redessiner a l'entree en raid ; son injection de defaut est restee VERTE, ce qui voulait dire qu'elle ne servait a rien : `RebuildRoster` redessine deja par `AssignRosterToButtons`. Lister les appelants avant d'ajouter une garde, pas apres.
- La page Apparence passe a 670 px de haut. Sans le defilement de la 1.6.7, ces quatre reglages n'auraient eu nulle part ou aller.
- Tests : 1 265 a 1 292.

## 1.6.7

**Les pages de reglages defilent.** Ce n'est pas un confort : c'etait le blocage.

- La page General n'avait plus une seule rangee libre, et la page Apparence n'a accueilli sa quatrieme qu'en rendant huit pixels sur le cadre d'apercu. Le choix du son de la 1.6.6 est reste sans bouton pour cette seule raison. La zone de contenu de la fenetre est desormais une zone de defilement, **chaque page declare sa hauteur**, et changer de page remet cette hauteur et repart du haut — sans quoi une page courte heritait du defilement de la longue et s'ouvrait a mi-hauteur.
- **Le choix du son a son bouton**, page General. Il fait tourner la liste : une liste deroulante pour quatre entrees serait un menu de plus a ouvrir pour un choix qui se fait a l'oreille. La page General est passee de 550 a 596 px de haut, ce qui n'aurait tout simplement pas ete possible avant.
- **La page d'Aide n'a plus sa propre zone de defilement.** Imbriquee dans celle de la fenetre, deux barres se seraient disputees la meme molette. L'annonce « la page continue plus bas » vit maintenant sur la FENETRE : posee sur la page, elle defilait avec elle et disparaissait juste au moment ou elle sert.
- **La page Historique reste volontairement a 550 px.** Sa molette sert a sa pagination : si elle avait besoin de defiler, les deux gestes se disputeraient le meme geste. Un test tient cette contrainte.
- **Un nouveau piege, et son garde-fou.** Une hauteur declaree trop courte ne se voit pas a l'ecran : la page defile simplement moins loin, et le dernier controle devient inatteignable. Le controle de recouvrement mesure desormais chaque page dans SA hauteur declaree, et refuse tout controle qui la depasse.
- Tests : 1 255 a 1 265.

## 1.6.6

- **Le son d'alerte se choisit parmi les sons du jeu**, par `/cleansive sound`. Les identifiants sont LUS dans `SOUNDKIT` au moment ou on en a besoin, jamais recopies : un identifiant invente ne leve pas, il ne joue rien — et une alerte silencieuse serait pire que le son juge trop aigu, qui etait la demande d'origine. Un son que votre client ne connait pas disparait donc de la liste, et un choix devenu introuvable retombe sur le fichier livre.
- **Une limite dite plutot que decouverte.** Le registre d'alertes de Blizzard ne prend qu'un fichier son, et un son integre du jeu s'adresse par identifiant : les afflictions que le client protege gardent donc le son livre. L'addon le dit au moment du choix, une fois, plutot que de laisser decouvrir deux sons differents.
- **Le reglage n'a pas encore de bouton.** Les pages de reglages sont pleines : la page General n'a plus une seule rangee libre, et la page Apparence n'a accueilli sa quatrieme qu'en rendant huit pixels sur le cadre d'apercu. Ajouter un controle de plus demande d'abord de rendre les pages defilantes.
- Tests : 1 239 a 1 255.

## 1.6.5

- **La couleur de classe sur les cases au repos.** Demande d'un joueur : reconnaitre qui est qui sans lire un nom, que les petites cases ne peuvent de toute facon pas afficher. Nouvelle option sur la page Apparence, **eteinte par defaut**. Une case affligee n'est jamais concernee : sa couleur dit le type de dissipation, et c'est la seule raison d'etre de la grille. La couleur est dessinee a l'opacite de repos que vous avez choisie — montez-la si vous voulez que les classes ressortent.
- **La palette fait autorite, jamais la couleur rendue.** Un pretre EST blanc : deduire « classe illisible » d'une couleur blanche aurait rendu tous les pretres gris. Une classe que la palette ignore, ou que le client refuse de lire — elle est secrete-capable en 12.1 — rend la case neutre, pas blanche : un blanc a 18 % ressemblerait a une classe de plus.
- **La page Apparence a ete redistribuee** pour loger la quatrieme rangee de reglages. Les huit pixels rendus par le cadre d'apercu paient la place : rien n'a ete tasse ailleurs, et le controle de recouvrement le verifie.
- **Le harnais repondait « blanc » a toute classe, y compris a une classe inexistante.** Impossible d'y distinguer une classe connue d'une classe illisible : tout code qui interroge la palette passait pour verifie sans l'etre. La palette du bouchon est desormais partielle mais honnete — une cle inconnue rend nil, comme chez Blizzard.
- Tests : 1 228 a 1 239.

## 1.6.4

Retour d'un joueur sur le forum, et le controle de mise en page pousse au bout.

- **L'addon ne sonne plus pour des cases qu'il a decide de ne pas afficher.** « Afficher en raid » eteint, la grille disparaissait — et l'alerte continuait. Le pilote de visibilite est SECURISE : il decide seul et ne rend jamais son verdict a Lua, donc le son ne le consultait pas. Pire, le registre sonore natif est joue par le CLIENT : une fois pose, il sonnait tout seul, grille eteinte ou non. Se taire cote Lua n'aurait donc rien change ; les enregistrements sont maintenant RETIRES a l'entree dans un contexte masque, et reposes a la sortie. La regle est desormais celle-ci : on entend exactement ce qu'on voit. L'essai demande depuis les reglages, lui, se joue toujours.
- **La macro de visibilite est desambiguisee.** Selon la lecture que le client fait de « group:party », un raid est OU N'EST PAS un groupe. Dans la premiere, « Afficher en raid » eteint ne servait a rien : la clause de groupe rallumait la grille en raid, et le son avec elle. Impossible de trancher hors du client : la macro est ecrite pour dire la meme chose dans les deux lectures. Un test evalue la macro et compare son verdict au miroir Lua sur les 96 combinaisons.
- **Le controle de recouvrement descend maintenant dans les controles, et couvre la barre laterale.** Il avait ete arrete a mi-chemin en 1.6.3 parce que la descente accusait huit controles parfaitement lisibles. La cause n'etait pas la descente mais le modele de largeur : il ESTIMAIT la largeur d'un texte sans taille posee, et l'estimation etait trop large. Un texte sans largeur posee est desormais declare non mesurable. Un modele qui surestime accuse ; un modele qui se tait laisse passer — et entre les deux il n'y a pas de symetrie, une fausse accusation apprend a ignorer le test. Les neuf recouvrements du 30/08 venaient tous d'elements a taille posee : rien n'est perdu, et un onglet pose sur un autre dans la barre laterale est maintenant vu.
- Les deux lignes d'etat de la page General ont une hauteur RESERVEE : une formulation plus longue ne peut plus descendre en silence dans la carte de profil.
- Tests : 1 219 a 1 228. Le parcours recursif rendait le controle quadratique — l'index des enfants se construit desormais en une passe.

## 1.6.3

Correctifs de mise en page releves sur captures en jeu, et reparation de
l'outil qui aurait du les trouver avant vous.

- **Neuf recouvrements corriges dans la fenetre de reglages.** Une phrase de 560 px passait en travers de deux interrupteurs ; le bloc « Ou la grille apparait » mordait sur les boutons d'outils rapides ; la description de l'Historique passait sous « Copier cette liste » ; le texte d'etat du pied passait sous « Reinitialiser cette page » et « Mode test », sur trois pages sur cinq. Et en bas de la page General, quatre textes se disputaient trois lignes : le resume de profil repetait mot pour mot ce que la carte posee dessus annoncait deja — il a disparu, l'information reste, dite une seule fois.
- **Le detecteur de recouvrement avait deux angles morts, et c'est le vrai defaut.** Il ecartait en silence tout texte a qui on avait donne une largeur sans hauteur — c'est-a-dire toutes les phrases d'explication, celles qui reviennent a la ligne. Il ne comprenait que deux ancrages sur neuf et aucun ancrage relatif a un autre cadre. Et il ne comparait que les pages, jamais le pied de la fenetre, qui n'appartient a aucune d'elles. Il resout desormais la geometrie pour de bon : les neuf ancrages, les chaines d'ancrages relatifs, la hauteur reelle d'un texte qui revient a la ligne, et le pied de fenetre. Les neuf recouvrements sont tombes du premier coup.
- **Ce que le detecteur ne fera pas.** La descente a l'interieur des controles a ete essayee puis retiree : la largeur d'un texte y est estimee, pas mesuree, et cette estimation accusait huit controles que les captures montrent parfaitement lisibles. Un controle mesure faux qui accuse est pire qu'un controle non mesure. Tout ce qui doit etre surveille reste donc enfant direct de sa page.
- Un invariant trouve en chemin est desormais garde : la couche de recharge doit avoir exactement la taille de l'ancre securisee qu'elle decalque, sans quoi tous les voiles se decalent. Les deux tailles etaient posees a deux endroits eloignes, sans rien pour les lier.
- Tests : 1 208 a 1 219.

## 1.6.2

Trois finitions d’interface relevees par l’audit de la 1.6.

- **La grille dit elle-meme qu’elle est en apercu.** L’information ne vivait que dans la fenetre d’options : une capture d’ecran, ou un retour au clavier apres une pause, ne disait plus si les cases rouges etaient de vraies afflictions. Une plaque **TEST** parait a cote de la grille tant que l’apercu est ouvert. Elle vit sur la couche non protegee, n’entre jamais dans la hierarchie securisee et n’avale aucun clic.
- **La page d’Aide dit qu’elle continue plus bas.** Elle fait plus de deux ecrans et la barre de defilement de Blizzard se confond avec le fond sombre du panneau : on arrivait au bas des Commandes en croyant la page finie. Une bande d’indice occupe desormais une bande reservee sous la zone de lecture — elle ne recouvre aucune ligne, et s’efface des qu’il n’y a plus rien a lire.
- **Les fenetres se remettent a l’echelle quand l’ecran change.** Le calcul ne se faisait qu’a la creation : changer de resolution, passer en fenetre ou bouger l’echelle de l’interface laissait la fenetre a l’ancienne taille jusqu’au prochain `/reload`. `UI_SCALE_CHANGED` et `DISPLAY_SIZE_CHANGED` rejouent le calcul pour chaque fenetre. Le plancher de lisibilite de 0,70 est conserve : il ne se declenche qu’en dessous de 530 unites de hauteur utile, ce que le client ne produit pas — aucun chemin de secours n’a donc ete ajoute pour un cas que rien ne peut atteindre.
- Tests : 1 180 a 1 208. Le harnais retient desormais l’echelle d’une fenetre et la position d’une zone de defilement, que le bouchon generique rendait indiscernables.

## 1.6.1

Corrections issues d’un audit externe de la 1.6 et de captures d’écran en jeu.

- **Trois pages avaient des libellés empilés les uns sur les autres.** J’avais ajouté des contrôles à des positions déjà occupées, sans aucun moyen de le voir. Le harnais mesure désormais la géométrie de chaque contrôle et **refuse tout recouvrement** : quinze collisions ont été trouvées et corrigées. Au passage, les règles de visibilité forment un groupe nommé, et le regroupement des dissipations manuelles a rejoint la page Dissipations — où sa remise à zéro était déjà rangée.
- **L’aperçu ne peut plus être ouvert en plein combat.** Il ne pouvait alors pas reconstruire la liste des unités : de vraies unités recevaient de fausses afflictions, avec fausses cases rouges et fausse alerte, au moment où l’addon doit être le plus fiable. La commande entière est refusée et le dit — en garder l’effet caché aurait été une commande à moitié appliquée.
- **Une base abîmée est de nouveau entièrement réparée.** Les bornes vivaient dans une seconde liste écrite à la main, qui avait pris huit réglages de retard : `testUnits = « beaucoup »` repartait tel quel. Il n’y a plus de seconde liste — elle se déduit de la déclaration des réglages, et un test vérifie qu’aucun n’y échappe.
- **L’archive 1.6 contenait trois dossiers vides** venus d’une réécriture d’historique. Un dossier vide ne contient aucun fichier : il échappait entièrement au contrôle. Ce qui commence par un point est désormais refusé, vide ou non.
- **Le cumul réel d’alertes sonores est mesuré.** Pendant un changement de canal, le nouvel enregistrement existe un instant à côté de l’ancien, et la table ne le voyait pas. `/cleansive soundstatus` annonce maintenant les enregistrements vivants et le maximum atteint. Mesurer avant de décider.
- Le collage d’un texte démesuré dans l’import est refusé plutôt que traité. Le tri par rôle annonce l’ordre qu’il produit vraiment. Trois lignes du changelog embarqué avaient été mangées par mon propre outillage et sont réparées.
- Tests : 1 146 à 1 180, plus un contrôle de mise en page.


## 1.6

Cette version rassemble le travail mené à partir de l’étude des addons
concurrents : environ 110 des 176 points retenus y sont passés, en vingt et une
étapes.

**Ce que vous pouvez faire et que vous ne pouviez pas :**

- **Voir votre grille en raid sans être en raid.** L’aperçu la complète jusqu’à quarante cases inertes, ce qui permet enfin de régler taille, espacement et position d’une grille de raid — et d’en faire une capture. Une case d’aperçu ne porte aucune unité sécurisée, n’est jamais présentée au moteur d’auras protégé et n’entre jamais dans le registre sonore.
- **Partager un profil.** Export et import en texte, avec la liste exacte de ce qui changerait montrée avant que quoi que ce soit ne bouge. Ne partent jamais : votre position à l’écran, votre langue, et vos listes de priorité et d’exclusion — elles contiennent des noms de joueurs.
- **Savoir ce que Cleansive a compris.** `/cleansive spells` liste les sorts détectés, `/cleansive soundstatus <id>` explique pourquoi une affliction reste muette, `/cleansive alerts` montre les dernières décisions sonores et leur raison, `/cleansive order` explique l’ordre des cases, `/cleansive coverage` dit ce que la liste de saison couvre type par type.
- **Signaler un problème correctement.** `/cleansive diag copy` produit un rapport d’un bloc, sans nom de personnage, avec la révision exacte du code.
- **Surveiller racines et étourdissements.** Rien n’est surveillé par défaut : Cleansive apprend ce qu’il voit, vous choisissez. Une entrave ne masque jamais une affliction.
- **Trouver un réglage.** Une recherche sans accents ni majuscules, qui dit sur quelle page aller et vous y emmène. Une page Aide avec toutes les commandes, un dépannage par symptôme, et ce que Cleansive **ne peut pas** faire.
- Quatre points de départ pour l’allure, une remise à zéro limitée à la page affichée, deux clics avant toute destruction, trois règles combinables pour l’endroit où la grille apparaît, un ordre par rôle ou par classe, et des fenêtres qui retiennent leur place.

**Ce qui a été réparé en profondeur :**

- Le son se remplace sans période de silence, et un remplacement refusé conserve l’alerte qui fonctionnait.
- Le moteur d’auras protégé n’est plus reconstruit au milieu d’une rencontre. Un emplacement d’aura ne se retire jamais : le reconstruire pendant un boss coûte des emplacements définitifs.
- Trois appels protégés jetaient leur résultat, transformant un refus du client en silence. C’est ce mécanisme qui avait masqué 480 refus d’affichage jusqu’à ce qu’on les compte.
- L’interface a cessé de promettre ce qu’elle ne fait pas : un bouton de souris sans sort derrière, un interrupteur de noms inopérant sur de petites cases, un aperçu qui montrait des éléments coupés.

**Sous le capot :** 1 146 tests et 13 contrôles statiques, dont un qui vérifie
que la chaîne de publication ne peut pas publier sans être passée par la
vérification, et un autre que rien de superflu n’entre dans l’archive. Chaque
correction a été éprouvée en réinjectant le défaut pour voir les tests virer au
rouge.

**Ce qui n’est pas fait, et pourquoi :** les points touchant au dessin et à
l’ordre d’affichage — reparentage des décorations, second bord d’affliction,
icône de rôle — ne se prouvent pas hors du jeu et attendent une vérification à
l’écran. Le catalogue sonore par instance attend des données de terrain, pas du
code.


## 1.5.67

- **L’aperçu des réglages mentait sur deux points.** Il affichait la lettre de clic et le chiffre de recharge même quand vous les aviez coupés : il promettait une case que la vraie grille ne dessine pas. Un aperçu qui ne suit pas les réglages est pire qu’aucun aperçu, parce qu’il fait douter de la grille.
- **Le dépannage dit de capturer le diagnostic AVANT un `/reload`.** Un rechargement remet tout en place et efface justement l’état qu’on voulait montrer.
- Un test écrit dans ce lot a été **retiré** : il vérifiait que le coin choisi de la grille ne bouge pas quand le groupe grandit, mais le harnais ne donne aucune géométrie aux cadres — rien ne pouvait déplacer l’ancre et le test passait quoi qu’on injecte. Un test qui ne peut pas rougir vaut moins que pas de test : il occupe la place de celui qui manque. Ce point rejoint les vérifications à faire en jeu.
- Tests : 1139 à 1146.


## 1.5.66

- **`/cleansive control copy`** sort le catalogue des pertes de contrôle observées en un bloc, avec le lieu et ce que vous surveillez. Copier ne vide rien : on copie avant de vider, jamais l’inverse.
- **Un profil partagé ne peut plus emporter une clé non déclarée.** Le test précédent affirmait que le catalogue observé ne partait pas — c’était vrai par construction, donc aucun défaut ne pouvait le rendre faux : il rejouait la conception au lieu de l’éprouver. Il vérifie désormais que **chaque clé sortante est reconnue**, ce qui casse le jour où quelqu’un en ajoute une qui porte du personnel.
- Deux comportements déjà présents sont désormais verrouillés par un test plutôt que réécrits : un bouton grisé se repeint immédiatement au lieu d’attendre que la souris sorte, et une remise à zéro des réglages n’efface pas ce que Cleansive a observé.
- Tests : 1127 à 1139.


## 1.5.65

- **Le harnais de tests vit désormais dans le dépôt.** Il vivait à côté, ce qui voulait dire deux copies possibles d’une même suite — et la correction finit toujours par atterrir sur celle que personne ne lance. La CI GitHub exécute maintenant exactement la même suite que moi, sur exactement les mêmes fichiers.
- **La chaîne de publication est coupée en deux.** Le travail de vérification ne tient **aucun** secret de publication : un test capable d’atteindre la clé CurseForge serait un test capable de la divulguer. Et rien ne peut publier sans être passé par lui — une suite rouge ne doit jamais atteindre une page de téléchargement.
- **Un treizième contrôle statique lit le workflow lui-même** et vérifie ces deux règles. Elles sont faciles à défaire d’une ligne distraite, et invisibles une fois défaites.
- Le contrôle d’archive lit désormais les exclusions de `.pkgmeta` au lieu d’en tenir une seconde liste à côté, qui aurait divergé au premier ajout.
- Tests : 1127, plus un contrôle statique.


## 1.5.64

- **Le rapport porte la révision exacte du code**, pas seulement le numéro de version : deux archives d’une même version peuvent différer, et sans la révision un signalement ne désigne aucun état du dépôt. Sur une copie de travail le champ vaut encore le jeton de l’empaqueteur — il n’est alors **pas affiché**, parce qu’un artefact de fabrication n’est pas une information.
- **Ce que la construction de la grille a coûté** : temps, cases construites, emplacements obtenus, première erreur.
- **Qui pilote quelle case.** Deux moteurs coexistent, celui de Blizzard et le repli Lua, et rien ne disait lequel tenait combien de cases — c’est pourtant la première question devant un affichage surprenant.
- Un test vérifie que **sans aucun sort de dissipation, Cleansive ne fait presque rien** : aucun conteneur d’auras protégé n’est créé et aucune alerte sonore n’est enregistrée pour rien.
- Tests : 1108 à 1127.

## 1.5.63

- **« Pourquoi ça n’a pas sonné » a enfin une réponse.** La décision était prise à chaque affliction et ne laissait aucune trace. `/cleansive alerts` montre les douze dernières : jouée, même affliction qu’avant, aucune affliction, son coupé, addon coupé, ou le client n’a rien joué. **Le son coupé et un fichier qui n’a pas pu être lu ne se confondent plus** : ce sont deux problèmes différents et deux corrections différentes.
- **Le test de portée dit avec quel sort il a jugé.** Il répondait oui ou non sans jamais nommer la capacité qui avait servi ; quand la réponse surprend, c’est la première chose à savoir. La source entre dans le rapport copiable.
- **`/cleansive coverage`** dit ce que la liste de saison couvre type par type. Un total de 46 ne disait pas si les malédictions étaient servies ou oubliées. Un type désactivé y est distingué d’un type que rien ne peut retirer.
- Tests : 1092 à 1108.

## 1.5.62

- **Trois appels protégés jetaient leur résultat.** `pcall` empêche l’erreur Lua, il ne dit pas que l’opération a eu lieu : un retour ignoré transforme un refus du client en silence, ce qui est exactement ce qui avait masqué les 480 refus de mise en forme jusqu’à ce qu’on les compte. Un balayage qui refuse de s’effacer se cache désormais au lieu d’afficher un compte à rebours faux ; un pilote d’attribut qui survit est signalé, parce qu’il garde le clic pointé sur l’ancien véhicule. **Un onzième contrôle statique** interdit qu’un `pcall` reparte aveugle.
- **Un douzième contrôle** vérifie qu’aucune cellule ne va vivre dans l’arbre d’un autre addon. La règle est facile à tenir aujourd’hui et facile à oublier le jour où une intégration arrivera : mêler deux arbres de sécurité, c’est laisser l’erreur de l’un fermer l’autre.
- **L’aperçu appartient à qui l’a ouvert.** Ouvert depuis la fenêtre de réglages, il se ferme avec elle ; ouvert à la commande, une fenêtre que vous n’avez pas ouverte n’a rien à en dire.
- Le harnais déclenchait l’état d’une fenêtre sans déclencher ses scripts : `OnShow` et `OnHide` n’étaient exercés par aucun test, et tout ce qu’ils font passait pour vérifié sans l’être. C’est réparé, et la suite reste verte.
- Tests : 1082 à 1092, plus deux contrôles statiques.

## 1.5.61

- **Sortir du combat n’est pas sortir de la rencontre.** Un changement de spécialisation en plein combat laissait une reconstruction du moteur d’auras en attente, rejouée au premier répit — c’est-à-dire potentiellement entre deux vagues d’un boss. Un emplacement d’aura ne se retire jamais : reconstruire au milieu d’une rencontre coûte des emplacements définitifs pour deux secondes de calme. Le travail attend maintenant `ENCOUNTER_END`. Hors rencontre, la fin de combat suffit toujours — il ne faut pas attendre un signal qui ne viendra jamais en monde ouvert.
- **La page Général s’ouvre sur l’essentiel** : le profil actif, et l’état du moteur d’auras protégé en une phrase — non utilisé, pas encore en place, en attente d’un moment calme, incomplet, ou pilotant toutes les cases.
- Tests : 1059 à 1082.

## 1.5.60

- **Glisser un curseur de taille ne replace plus la grille à chaque cran.** Un glissement complet déclenchait des dizaines de repositionnements de 82 cases dont un seul comptait. Seul le dernier s’applique désormais. L’aperçu des options, lui, reste immédiat : c’est celui que vous regardez pendant le geste.
- **« Afficher les noms » n’a plus l’air cassé.** Sous 16 px il n’y a pas la place pour un nom, et l’interrupteur ne faisait donc rien sans rien dire. L’interface l’explique maintenant, et l’explication disparaît dès qu’elle n’a plus lieu d’être.
- **`/cleansive control clear`** vide la liste des pertes de contrôle observées sans effacer les types que vous avez choisi de surveiller : ce que Cleansive a appris et ce que vous avez décidé sont deux choses.
- Un contrôle vérifie désormais que **chaque réglage explique ce qu’il fait**. Aucun n’était muet, mais rien ne garantissait que le prochain ne le serait pas.
- Un test vérifie qu’un talent qui **remplace** un sort par un autre sans changer leur nombre est bien vu : un rafraîchissement qui se fierait au compte n’aurait rien remarqué.
- Tests : 1044 à 1059.

## 1.5.59

- **L’infobulle ne promet plus un bouton qui ne fait rien.** Elle annonçait « Souris 4 : troisième dissipation » à toutes les spécialisations, y compris à celles qui n’ont qu’un seul sort. Elle n’annonce désormais que ce qui existe vraiment.
- **Cleansive crédite ce dont il a appris** : Decursive, qui a défini ce genre d’addon, puis Salve, le Decursive de Zhaou, Simple Decursive, ClickCleanse, K Decurse et LFDecurse. Leurs comportements ont servi de leçon et ont été réécrits depuis l’API de Blizzard. Aucune ligne de leur code n’est ici, et leurs licences ne l’auraient pas permis.
- **Avertissement d’installation** : l’archive « Source code » générée automatiquement par GitHub n’est pas un addon utilisable.
- Tests : 1036 à 1044.

## 1.5.58

- **Cleansive peut signaler racines, étourdissements et autres pertes de contrôle** sur les membres du groupe. Vérification faite dans les définitions d’API avant d’écrire une ligne : `C_LossOfControl.GetActiveLossOfControlDataByUnit` accepte bien un jeton d’unité, et pas seulement `player`.
- **Rien n’est surveillé par défaut.** `/cleansive control` liste uniquement ce que Cleansive a *réellement observé*, avec le lieu, et vous choisissez les types qui méritent une marque. Un type absent de cette liste n’est pas la preuve qu’il n’existe pas : c’est que Cleansive ne l’a pas encore vu. Demander à surveiller un type jamais vu est refusé et dit, pas accepté en silence.
- **Une entrave ne masque jamais une affliction.** Elle n’utilise la bordure que sur une case qui n’a rien à dissiper. Dissiper reste le travail.
- La donnée peut être secrète sous restriction. **Un compte secret n’est jamais utilisé comme borne de boucle** — la comparaison lèverait dans le client. Un refus de lecture veut dire « inconnu », jamais « aucune entrave ».
- Tests : 1018 à 1036. Le test du compte secret a été réécrit : la première version vérifiait que rien n’était rendu, ce qui restait vrai même sans le garde-fou. Il compte désormais les lectures, qui doivent être nulles.

## 1.5.57

- **Le registre sonore dit son état en une phrase** au lieu d’une suite de nombres : coupé, indisponible, pas encore mis en place, en cours, dégradé, ou actif. Un joueur qui lit « 46/46, 0 en attente, 0 erreur » doit encore conclure lui-même ; conclure est le travail de l’addon. Un remplacement préservé et des unités écartées par le budget comptent comme **dégradé**, pas comme un succès.
- **Le balayage du temps d’affliction se coupe séparément du chiffre de recharge.** Ce sont deux informations différentes : l’une compte l’affliction, l’autre compte votre sort.
- **`/cleansive size 33` et `/cleansive spacing 4`** pour qui veut une valeur exacte plutôt qu’un curseur.
- La première version de l’interrupteur de balayage n’était pas vérifiée : l’injection est restée verte. Le test observe désormais l’appel réel au moteur, pas la valeur du réglage.
- Tests : 985 à 1018.

## 1.5.56

- **L’ordre des cases se choisit** : par groupe de raid (inchangé, et toujours le défaut parce qu’il répartit le travail entre plusieurs dissipeurs), par rôle, ou par classe. Le tri par rôle place les tanks puis les soigneurs devant. **Votre liste de priorité passe avant tous les modes** — elle décide, ils arrangent le reste.
- Le rôle est lu **une fois par reconstruction** et rangé dans la fiche de l’unité. Le lire dans le comparateur aurait appelé l’API à chaque comparaison, soit des centaines de fois par tri en raid.
- **L’archive livrée est contrôlée avant de partir** : licence présente, changelog qui parle de la version du `.toc`, README d’accord avec elle, aucun jeton de version resté tel quel, aucun BOM, aucune fin de ligne CRLF, aucun reste de développement. Écrit après avoir constaté que le premier contrôle du changelog acceptait « 1.5.55bis » pour « 1.5.55 » : il comparait un préfixe, il compare désormais la ligne entière.
- Tests : 975 à 985, plus un dixième contrôle statique.

## 1.5.55

- **Trois règles combinables pour l’endroit où la grille apparaît** : seul, en groupe, en raid. Elles se combinent avec la règle « seulement en combat » plutôt que de la remplacer. Tout passe par le pilote de visibilité sécurisé de Blizzard, donc les règles continuent de s’appliquer pendant le combat, quand Lua ne peut plus rien.
- **Aucun pilote n’est posé quand il ne pourrait dire que « affiche ».** Une règle sécurisée ne se retire pas en combat : en poser une pour rien, c’est se lier les mains sans contrepartie.
- **La grille reste visible pendant que vous la réglez.** Ouvrir la fenêtre de réglages suspend les règles de masquage, les fermer les rend. Régler la taille et la position d’une chose invisible n’avait pas de sens.
- Tests : 964 à 975.

## 1.5.54

- **Une recherche dans les réglages.** Elle ignore les accents et les majuscules — on tape « opacite » et on trouve « Opacité » — et elle cherche aussi dans les textes d’aide, parce qu’on cherche souvent par ce qu’un réglage *fait* plutôt que par son nom exact.
- **Chaque résultat dit sur quelle page aller**, en clair, et cliquer dessus y emmène. Un résultat qui donne le nom sans le chemin est un cul-de-sac.
- L’index est alimenté par les fabricants de contrôles eux-mêmes : une liste tenue à côté aurait divergé dès le premier réglage ajouté.
- Tests : 943 à 964.

## 1.5.53

- **L’infobulle d’une case dit pourquoi elle est là** : parce que c’est vous, parce que l’unité figure à telle position de votre liste de priorité, ou parce que c’est une case d’aperçu. L’ordre était déjà déterministe ; il n’était simplement écrit nulle part.
- **Le nom prend la couleur de sa classe** dans l’infobulle.
- **L’historique retient où chaque affliction a été vue.** Une instance est retenue par son **numéro**, pas par son nom traduit : un client français et un client anglais doivent pouvoir parler du même donjon. Dehors, la carte suffit et aucun numéro d’instance n’est inventé.
- **La liste peut sortir du jeu en un bloc** avec le lieu à côté de chaque identifiant. Un identifiant seul n’est vérifiable par personne ; avec le lieu, il se rejoue.
- La fenêtre de copie est devenue unique et retitrable au lieu d’être dupliquée. Deux fenêtres presque identiques dériveraient, et la correction irait sur celle que le rapporteur n’a pas ouverte.
- Un contrôle de type redondant a été retiré : `palette[42]` rend déjà `nil`, et `nil` était déjà traité une ligne plus bas. Un garde-fou de plus n’est pas un garde-fou de mieux.
- Tests : 924 à 943.

## 1.5.52

- **Quatre points de départ pour l’allure de la grille** : Compact, Lisible, Raid, Minimal. Ce sont des points de départ, pas des modes : chacun écrit des réglages ordinaires que vous modifiez ensuite un par un. Rien ne mémorise « le préréglage sur lequel vous êtes » — dès que vous bougez un curseur ce serait faux, et un libellé qui ment est pire que pas de libellé.
- **La remise à zéro ne concerne plus que la page affichée.** Vouloir retrouver sa grille ne devrait pas coûter ses listes et ses filtres. Le bouton disparaît sur les pages qui n’ont rien à remettre à zéro, plutôt que de promettre une action vide.
- **Deux clics avant de détruire**, et pas une fenêtre de confirmation : une popup coupe le geste et se valide sans être lue. Le bouton annonce qu’il attend, se désarme tout seul au bout de quelques secondes, et se désarme aussi quand vous changez de page — il parle de la page affichée.
- Tests : 889 à 924, vérifiés par réinjection de cinq défauts.

## 1.5.51

- **Le pied de la fenêtre de réglages dit enfin la vérité.** Il affichait « Modifications enregistrées instantanément » en toutes circonstances, y compris en plein combat où c’est faux. Il annonce maintenant le combat, le nombre exact de changements qui attendent la fin du combat, ou le fait que Cleansive est désactivé — et il compte **les mêmes** reports que la plaque à côté de la grille : deux réponses différentes à « est-ce que quelque chose attend ? » seraient pires qu’aucune.
- **Un réglage qui ne s’applique pas ne reste plus affiché.** Le son coupé, tout ce qui le règle — canal, budget, test, état — disparaît au lieu de rester là à suggérer qu’il sert à quelque chose.
- **Les quatre fenêtres déplaçables retiennent leur place** : réglages, listes, filtres, partage de profil et diagnostic. La position est enregistrée dans la section globale et non dans un profil : la fenêtre est unique, les profils sont nombreux. Un ancrage inconnu ou une coordonnée illisible est refusé plutôt que passé à `SetPoint`, qui lève.
- Tests : 870 à 889, vérifiés par réinjection de six défauts.

## 1.5.50

- **Un profil s’exporte et s’importe en texte**, depuis **Aide → Partager ce profil**. C’est la fonction que les concurrents mettent en avant et que Cleansive n’avait pas.
- **L’import lit d’abord et n’écrit qu’ensuite.** Le premier clic vérifie et affiche la liste exacte de ce qui changerait, réglage par réglage, avec la valeur de départ et celle d’arrivée. Rien n’est modifié tant que vous n’avez pas cliqué une seconde fois. Un import qui s’applique au premier clic, c’est une configuration perdue sans retour — et la chaîne vient en général de quelqu’un d’autre.
- **La validation est stricte et bavarde.** Une clé inconnue, une valeur hors bornes ou un ordre de types incomplet sont refusés *et nommés*, jamais rabotés en silence : un import à moitié appliqué qui se déclare réussi est pire qu’un refus. Le texte n’est jamais exécuté — un analyseur clé/valeur ne peut rien lancer.
- **Ce qui ne part jamais** : votre position à l’écran (c’est celle de l’expéditeur), votre langue (elle est globale), et vos listes de priorité et d’exclusion — elles contiennent des noms de joueurs.
- **Copier un profil vers une autre spécialisation** du même personnage, y compris une spécialisation jamais jouée.
- Tests : 824 à 870, vérifiés par réinjection de dix défauts, dont la fuite des noms de coéquipiers et l’import qui s’applique trop tôt.

## 1.5.49

- **Une page Aide dans l’addon.** Trois blocs dans une seule zone de défilement : toutes les commandes, un dépannage par symptôme, et un « À propos » avec la version, la licence et l’adresse de signalement — rendue copiable, parce qu’un addon ne peut pas ouvrir un navigateur. Le bouton « Diagnostic copiable » y ouvre directement le rapport à joindre.
- Le dépannage explique les limites plutôt que de laisser croire à un bug : un identifiant protégé pendant le combat ne peut être nommé par aucun addon, une augmentation de charges n’est pas une nouvelle application, et les couleurs peintes par le moteur protégé appartiennent à Blizzard.
- Un test vérifie que **chaque commande est documentée dans les deux langues**. La première version ne lisait qu’une langue et laissait passer un trou dans l’autre.
- Tests : 810 à 824.

## 1.5.48

- **`/cleansive spells` dit ce que Cleansive a détecté.** Chaque sort de dissipation trouvé, avec son identifiant, le clic auquel il est attaché — ou le fait qu’il doit être lancé à la main, sur soi ou en zone — et les types qu’il couvre. Un type que vous avez désactivé reste affiché et signalé comme tel, plutôt que de disparaître et de laisser croire que le sort ne le couvre pas. « Il ne détecte pas mon sort » est la remontée la plus fréquente pour ce genre d’addon, et la réponse était déjà dans des données que Cleansive calculait sans jamais les montrer.
- **`/cleansive soundstatus <identifiant>` explique une affliction muette.** Il n’y a que cinq réponses possibles et Cleansive est le seul à savoir laquelle s’applique : l’identifiant n’est pas dans la liste de la saison, son type est désactivé, il est filtré, le budget d’enregistrement l’a écarté, ou il est bien enregistré et le problème est ailleurs. La réponse est lue dans le registre réel.
- **`/cleansive order` montre l’ordre des cases et sa raison** : vous, la liste de priorité, l’ordre du groupe, ou l’aperçu.
- **`/cleansive version`**, et **`prio clear` / `skip clear`** pour vider une liste sans ouvrir sa fenêtre.
- Le README dit désormais ce que Cleansive **ne peut pas** faire, où vivent les réglages, pourquoi une augmentation de charges ne resonne pas, et quoi joindre à un signalement.
- Deux garde-fous écrits pendant ce travail se sont révélés inatteignables et ont été retirés plutôt que gardés « au cas où ».
- Tests : 792 à 810, vérifiés par réinjection de sept défauts.

## 1.5.47

- **L’aperçu peut enfin montrer un raid.** Le mode test n’affichait que les unités réellement présentes : seul, il montrait une case. La grille se complète maintenant jusqu’au nombre demandé (1 à 40) avec des cases inertes, ce qui permet de régler la taille, l’espacement et la position d’une grille de raid — et de la prendre en capture — sans être en raid. Boutons 1 / 5 / 10 / 20 / 40 dans **Apparence → Aperçu en direct**, ou `/cleansive test 20`.
- **Une case d’aperçu ne touche à rien de réel.** Elle ne reçoit aucune unité sécurisée, elle n’est jamais présentée au moteur d’auras protégé, et elle n’entre jamais dans le registre sonore natif. Une demande plus petite que le groupe réel n’enlève personne : l’aperçu ne fait qu’ajouter.
- **L’aperçu n’allume plus toutes les cases d’un coup.** Par défaut la première case et une sur quatre s’allument, donc les deux états sont visibles à la fois. `/cleansive test all` et `/cleansive test healthy` forcent l’un ou l’autre.
- **Le début du combat referme l’aperçu.** Les afflictions de test s’éteignent immédiatement et les cases inertes disparaissent à la fin du combat, quand les attributs sécurisés peuvent de nouveau être réécrits.
- Un garde-fou écrit pendant ce travail s’est révélé inatteignable et a été retiré plutôt que gardé « au cas où ».
- Tests : 756 à 792, vérifiés par réinjection de six défauts.

## 1.5.46

- **Les alertes sonores sont maintenant remplacées sans période de silence.** Lors d’un changement de canal, de groupe ou de filtre, Cleansive ajoute chaque nouvel enregistrement natif avant de retirer l’ancien. Si `C_UnitAuras.AddAuraSound` est temporairement refusé, l’ancienne alerte qui fonctionne reste active et une reprise bornée est programmée.
- **Un remplacement sonore ne peut plus produire deux alertes durables.** Si l’ancien enregistrement refuse de se retirer après la création du nouveau, le nouveau est annulé et l’ancien est conservé. Un éventuel échec de cette annulation est mémorisé puis nettoyé au rafraîchissement suivant.
- **Le canal réel est suivi par enregistrement.** Un changement partiellement appliqué n’est plus présenté comme une réussite globale ; `/cleansive soundstatus` indique combien d’anciens enregistrements ont été préservés et combien de remplacements ont été annulés.
- **`/cleansive diag copy` ouvre un rapport sélectionné et copiable en un bloc.** Il rassemble version, restrictions actives, moteur d’auras, sons, recharge du sort, reports et refus utiles pour un ticket CurseForge, Wago ou GitHub.
- Cette revue compare Cleansive à Decursive/Zhaou’s Decursive, Salve, Simple Decursive, ClickCleanse, K Decurse, LFDecurse et Decursive121Compat. Les idées ont été réimplémentées indépendamment : aucun code GPL ni « All Rights Reserved » n’a été intégré au projet MIT.
- Tests : 743 à 756, vérifiés par réinjection.

## 1.5.45

- **Cleansive ne frappe plus a une porte que le client a declaree fermee.** Le releve d'une cle mythique reelle le tranche : 480 refus de mise en forme sur 480 avec le verrou de combat BAISSE -- `lock=0|ChallengeMode,Map,Chat` 450 fois, `lock=0|Encounter,ChallengeMode,Map,Chat` 30 fois. `InCombatLockdown()` annoncait l'addon libre d'agir pendant toute la course. La passe demande desormais `C_RestrictedActions.CheckAllowProtectedFunctions(auraButton, true)` avant ses neuf operations : un appel remplace neuf refus, et la passe est comptee comme differee, pas comme un echec.
- **La correction 1.5.44 par `IsForbidden` etait inerte, et le releve le prouve** : le compteur qu'elle alimente est absent de la base, donc l'appel a repondu faux 480 fois sur 480. `IsForbidden` dit si un objet a ete *declare* interdit ; ces objets ne le sont pas, c'est le contexte d'appel qui n'a pas la permission -- « from code tainted by an AddOn », comme le message le disait depuis le debut. Le garde est conserve pour le cas qu'il couvre reellement, et le vrai test a ete ajoute a cote.
- **La levee d'une restriction rejoue le travail differe.** `ADDON_RESTRICTION_STATE_CHANGED` est enregistre : une cle garde `ChallengeMode` actif longtemps apres le dernier pack, et `PLAYER_REGEN_ENABLED` se declenche pendant qu'elle court encore. Sans ce signal, la mise en forme reportee attendait un evenement sans rapport.
- `/cleansive diag` distingue desormais une passe differee faute d'autorisation d'un echec de restyle. Les deux etaient confondus, ce qui faisait passer un comportement correct pour une panne.
- Tests : 730 a 743, verifies par reinjection.

*Ce que cette version ne fait toujours pas : deplacer les elements decoratifs sur les cases appartenant a Cleansive plutot que sur les objets du moteur. C'est la correction de fond, elle change l'ordre d'affichage, et l'ordre d'affichage ne se prouve pas hors du jeu.*

## 1.5.44

- **Le bouton souris 4 alimente enfin le suivi de recharge.** La 1.5.43 l'a lie au troisieme sort mais ne l'a pas ajoute au registre des clics : le jeu lancait bien le sort, et la case gardait la recharge du precedent, ou aucune. La liaison securisee et le registre doivent nommer les memes boutons ; c'est desormais verifie par un test qui compare le bouton 4 a Ctrl + clic gauche plutot qu'a un numero d'emplacement fixe.
- **Un visuel que le moteur declare interdit n'est plus retente a chaque combat.** Un objet interdit ne redevient jamais autorise : il est desormais demande une fois via `IsForbidden`, retenu, et abandonne. Une session enregistree rejouait neuf appels refuses 690 fois pour rien. `/cleansive diag` compte maintenant les cases concernees au lieu d'accumuler des echecs de restyle qui n'en etaient pas.
- **Le budget de reprise sonore appartient au plan, pas a la session.** Deux refus definitifs sur un plan laissaient un plan different, qui n'avait jamais echoue, sans aucune reprise. Le compteur repart des que l'empreinte du plan change.
- Le README annoncait encore la 1.5.38 et ignorait les boutons 4 et 5. Les sections de version qui s'y accumulaient sont remplacees par un resume court renvoyant au changelog.
- Tests : 713 a 730, verifies par reinjection.

*Sur un point de l'audit, je ne suis pas d'accord : ces refus de mise en forme ne declenchent ni `ADDON_ACTION_FORBIDDEN` ni la fenetre proposant de desactiver l'addon. Un objet interdit et une fonction protegee sont deux mecanismes distincts -- le premier leve une erreur Lua ordinaire, que les gardes interceptent. Cinq sessions enregistrees le confirment : zero evenement de ce type depuis que la cause reelle a ete corrigee en 1.5.38. Le gaspillage etait reel, la fenetre non.*

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
