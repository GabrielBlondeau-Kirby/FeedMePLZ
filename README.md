# FeedMePLZ

Addon WoW : une icône ronde qui ouvre un petit cadre avec trois boutons pour
manger la nourriture de vos sacs.

- **Nourriture simple** : la nourriture sans buff.
- **Nourriture à stats** (bordure dorée) : celle qui donne « Bien nourri »,
  à garder pour les donjons.
- **Boisson** (bordure bleue) : pour les classes à mana. Masqué
  automatiquement pour les guerriers, voleurs (et chevaliers de la mort).

Chaque bouton choisit sa nourriture selon un **classement de critères**
configurable (par défaut : stack la plus basse, puis niveau le plus faible).
Exemple : 2 poulets + 20 champignons → mange un poulet.

## Utilisation

- Clic sur l'icône ronde : ouvrir / fermer le cadre.
- Clic sur un bouton du cadre : manger / boire.
- **Maj + glisser** l'icône : déplacer l'ensemble (position sauvegardée).
- **En combat**, le cadre se ferme tout seul et l'icône devient transparente
  (on ne peut pas manger en combat). Il se rouvre à la sortie du combat.
- `/fmp` : ouvre les options (aussi dans Échap → Options → AddOns).
- `/fmp lock` / `unlock` / `reset`
- **Icône de la minimap** : clic gauche = ouvrir / fermer le cadre,
  clic droit = options, glisser = la déplacer autour de la minimap.

### Options

- Boutons affichés dans le cadre, fermeture automatique en combat,
  verrouillage, réinitialisation de la position.
- Thèmes du cadre : Sombre, Doré, Arcane, Gangrène, Sang, WoWtesk (look de l’interface WoW).
- Ordre de priorité : cocher les critères utilisés et les ordonner avec ↑/↓.
  Le premier critère coché départage ; en cas d'égalité, on passe au suivant.
  Critères : stack la plus basse / haute, niveau requis le plus faible / élevé.
- Langue de l'interface : Auto (langue du jeu), English, Français.

## Détection

- Nourriture : l'objet lance le sort « Nourriture » (indépendant de la langue).
- À stats : sa description contient « Bien nourri » / « Well Fed ».
- Boisson : l'objet lance le sort « Boisson ».

## Installation

Copier le dossier `FeedMePLZ` dans `World of Warcraft/_forever_/Interface/AddOns/`.

## Licence

MIT — voir [LICENSE](LICENSE).
