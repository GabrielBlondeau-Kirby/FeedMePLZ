# FeedMePLZ

Addon WoW : deux boutons flottants qui mangent la nourriture de vos sacs.

- **Nourriture simple** : la nourriture sans buff.
- **Nourriture à stats** (bordure dorée) : celle qui donne « Bien nourri »,
  à garder pour les donjons.
- **Boisson** (bordure bleue) : pour les classes à mana. Masqué
  automatiquement pour les guerriers, voleurs (et chevaliers de la mort).

Chaque bouton choisit sa nourriture selon un **classement de critères**
configurable (par défaut : stack la plus basse, puis niveau le plus faible).
Exemple : 2 poulets + 20 champignons → mange un poulet.

## Utilisation

- Clic sur un bouton : mange.
- **Maj + glisser** : déplacer un bouton (position sauvegardée).
- `/fmp` : ouvre les options (aussi dans Échap → Options → AddOns).
- `/fmp lock` / `unlock` / `reset`
- **Icône de la minimap** : clic gauche = options, clic droit = afficher /
  masquer les boutons, glisser = la déplacer autour de la minimap.

### Options

- Afficher / masquer chaque bouton, verrouiller, réinitialiser les positions.
- Ordre de priorité : cocher les critères utilisés et les ordonner avec ↑/↓.
  Le premier critère coché départage ; en cas d'égalité, on passe au suivant.
  Critères : stack la plus basse / haute, niveau requis le plus faible / élevé.
- Langue de l'interface : Auto (langue du jeu), English, Français.

## Détection

- Nourriture : l'objet lance le sort « Nourriture » (indépendant de la langue).
- À stats : sa description contient « Bien nourri » / « Well Fed ».
- Boisson : l'objet lance le sort « Boisson ».

## Installation

Copier le dossier `FeedMePLZ` dans `World of Warcraft/_classic_era_/Interface/AddOns/`
(ou le dossier `_classic_`/`_anniversary_` selon votre version).

## Licence

MIT — voir [LICENSE](LICENSE).
