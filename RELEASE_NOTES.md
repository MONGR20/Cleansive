# Cleansive — journal des versions

Les versions 1.4.1 et suivantes sont des correctifs issus d'une revue de code.
Depuis la 1.4.5, les principales branches logiques corrigées sont couvertes
par une suite de tests de non-régression maintenue dans le dépôt de
développement. Les interactions
du moteur d'auras protégé restent également vérifiées en jeu.

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

L'historique complet est dans `CHANGELOG.md`, livre avec l'addon.
