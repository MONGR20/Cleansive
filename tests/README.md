# Tests de non-régression — Cleansive

Chaque test rejoue un défaut réellement livré à un moment de l'histoire de
l'addon. Le commentaire au-dessus indique la version où il est apparu : quand
un test casse, tu sais immédiatement quelle erreur est revenue.

La suite couvre aussi les corrections 1.4.8 du plan sonore, des véhicules,
des capacités personnelles, du mode affligés seulement et du cooldown exact.

## Lancer

```bash
cd j/tests
npm test
```

Sur une autre version :

```bash
node run.js ../work/Cleansive-1.5.0/Cleansive
```

Code de sortie 0 si tout passe, 1 s'il y a un échec, 2 si le Lua ne charge pas.

## Comment ça marche

Il n'y a pas d'interpréteur Lua sur la machine, donc `run.js` en embarque un :
**fengari**, une VM Lua écrite en JavaScript, installée en dépendance locale.
Aucune modification système.

`wow-mock.lua` remplace l'API de WoW. Les cadres répondent n'importe quelle
méthode par une fonction inerte ; seules les API dont les tests dépendent
vraiment sont implémentées. L'état du jeu — classe, spécialisation, sorts
connus, affaiblissements, combat — est piloté par `mock.state`.

`spec.lua` charge les huit fichiers de logique de l'addon dans un même espace
de noms, puis appelle les fonctions directement. Les deux fichiers purement
visuels (`EllesmereUX.lua`, `SetupWizard.lua`) sont volontairement exclus :
les charger demanderait une simulation de cadres bien plus lourde sans rien
couvrir de plus.

## Ce qui est couvert

- **`GetCurableAura`** — type désactivé ignoré, ordre de priorité respecté
  sans sortie anticipée, saignement absent de la liste saisonnière détecté.
- **`UpdateSpells`** — un sort de zone ou personnel n'occupe aucune case de
  clic, mais son type reste détectable.
- **Touche de dissipation** — aucune macro sans sort connu, nom sécurisé
  utilisé.
- **Profils** — aucun profil écrit tant que la spécialisation est inconnue,
  profil fantôme « 0 » supprimé, migration qui amorce les personnages
  suivants, clés obsolètes élaguées, historique absorbé sans perte.
- **Historique** — plafond de 100, éviction du plus ancien, chemin rapide
  quand l'aura est déjà la plus récente.
- **Roster** — focalisation hostile exclue, focalisation amicale incluse.
- **Plan sonore** — empreinte stable à état égal.

## Piège rencontré en écrivant ces tests

`NS.playerClass` est capturé une seule fois, au chargement de `Core.lua`.
Un test qui change `mock.state.playerClass` sans mettre `NS.playerClass` à
jour verra toutes ses vérifications de classe retomber sur la valeur de
chargement — et passer pour la mauvaise raison. La fixture `freshProfile`
pose désormais les deux. C'est exactement ce qui rendait le test du prêtre
faussement vert.

## Ajouter un test

Quand un défaut est trouvé, ajoute son scénario **avant** de le corriger, et
vérifie qu'il échoue. Un test qui n'a jamais échoué ne prouve rien.
