# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

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

L'historique complet est dans `CHANGELOG.md`, livre avec l'addon.
