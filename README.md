# Flux

Un lecteur RSS minimaliste pour macOS : tu ajoutes tes flux à la main, tu lis
dans une liste avec miniatures, et l'article s'affiche en entier dans l'app
(sans ouvrir le navigateur).

## Compiler

Prérequis : Xcode 15 ou plus récent (macOS 14 Sonoma minimum), et XcodeGen.

```bash
brew install xcodegen
cd Flux
xcodegen generate
open Flux.xcodeproj
```

Puis ⌘R dans Xcode. La signature est en « Sign to Run Locally » : aucun compte
développeur Apple n'est nécessaire.

Pour l'installer : Product › Archive, ou plus simplement Product › Build, puis
clic droit sur `Flux.app` dans le dossier Products › Show in Finder, et copie-la
dans /Applications.

## Fonctionnement

- **Ajout de flux** (⌘N) : colle l'adresse du flux ou celle du site. S'il s'agit
  d'une page web, l'app cherche le flux déclaré dans `<link rel="alternate">`,
  puis essaie les chemins classiques (`/feed`, `/rss`, `/atom.xml`…).
- **Formats** : RSS 2.0, RSS 1.0 (RDF) et Atom, parsés avec `XMLParser`.
- **Miniatures** : `media:thumbnail`, `media:content`, `enclosure`,
  `itunes:image`, puis première image du contenu, et en dernier recours
  l'`og:image` de la page de l'article.
- **Article complet** : si le flux ne fournit qu'un extrait (moins de ~700
  caractères), l'app télécharge la page et en extrait le contenu principal avec
  [Readability.js](https://github.com/mozilla/readability) (le moteur du mode
  Lecture de Firefox, licence Apache 2.0), exécuté dans un WKWebView invisible.
  Le résultat est mis en cache. Le bouton « Article complet / Version du flux »
  permet de basculer manuellement.
- **Lecture** : affichage dans un WKWebView avec JavaScript désactivé ; les liens
  s'ouvrent dans ton navigateur par défaut. Mode sombre pris en charge.
- **Renommer un flux** : clic droit › Renommer… (le nom d'origine reste
  disponible pour revenir en arrière).
- **Dossiers** (⇧⌘N) : repliables, avec le total des non-lus. Range un flux en
  le glissant sur un dossier, ou via clic droit › Déplacer vers. Glisser un flux
  sur l'en-tête « Flux » le sort de son dossier. Supprimer un dossier ne supprime
  pas ses flux. Clic droit › Personnaliser… pour changer le nom, la couleur et
  l'icône (SF Symbols).
- **Actualisation** : au lancement, à intervalle régulier (30 minutes par
  défaut), et avec ⌘R.
- **Réglages** (⌘, ou bouton ⚙ de la barre d'outils) : délai avant de marquer
  comme lu l'article ouvert (immédiatement, 5, 10 ou 30 secondes, jamais), marquer automatiquement comme lus les articles de plus de
  X jours (hors favoris), intervalle d'actualisation, durée de conservation des
  articles lus (2 mois par défaut ; non lus et favoris toujours conservés).
- **Données** : `~/Library/Application Support/Flux/Flux.store` (SwiftData).

- **Recherche** (champ de la barre d'outils) : dans le titre et le texte complet
  des articles de la vue courante (tous les articles, un dossier, un flux…).
- **Présentation** : liste détaillée ou vignettes (image + titre), au choix dans
  la barre d'outils. En vignettes, les flèches se déplacent dans la grille.
- **Sélection multiple** : ⌘-clic, ⇧-clic, ⇧↑/↓ ou ⌘A. Les boutons « Marquer la
  sélection comme lue / non lue » de la barre d'outils, le menu contextuel et les
  touches m / s s'appliquent à toute la sélection.
- **OPML** : Fichier › Importer des abonnements (⇧⌘I) reprend tes flux et leurs
  dossiers depuis un autre lecteur (NetNewsWire, Reeder, Feedly…) ; Fichier ›
  Exporter (⇧⌘E) les sauvegarde.
- **Apparence** : clair ou sombre selon macOS, ou forcé dans Réglages ›
  Général › Apparence (la vue de lecture suit aussi).
- **Langues** : interface en français et en anglais, selon la langue de macOS ;
  forçable dans Réglages › Général › Langue. Les traductions anglaises sont dans
  `Flux/en.lproj/Localizable.strings` (les clés sont les textes français).

## Raccourcis

| Raccourci | Action |
|---|---|
| ⌘N | Ajouter un flux |
| ⇧⌘N | Nouveau dossier |
| ⌘R | Actualiser |
| ⇧⌘K | Tout marquer comme lu (dans la vue courante) |
| ⌘, | Réglages |
| ↑ / ↓ | Naviguer dans la liste (avec ⇧ : étendre la sélection) |
| ⌘A | Sélectionner tous les articles de la liste |
| j / k | Article suivant / précédent |
| espace / ⇧ espace | Faire défiler l'article (en bas : article suivant) |
| m | Marquer comme lu / non lu (toute la sélection) |
| s | Ajouter aux / retirer des favoris (toute la sélection) |
| b | Ouvrir dans le navigateur |
| ⇧⌘I / ⇧⌘E | Importer / exporter les abonnements (OPML) |

## Structure

```
Flux/
├── FluxApp.swift          point d'entrée, base SwiftData
├── Models.swift           Feed, Article
├── FeedParser.swift       parser RSS/Atom + dates
├── FeedStore.swift        ajout, actualisation, miniatures, nettoyage
├── ArticleExtractor.swift Readability.js dans un WKWebView invisible
├── HTMLUtils.swift        texte brut, entités, images, découverte de flux
├── Net.swift              URLSession + erreurs
├── Settings.swift         clés et valeurs par défaut des réglages
├── Views/                 interface SwiftUI
├── Assets.xcassets        icône de l'app
└── Resources/Readability.js
Design/                    source de l'icône (script Python + PNG 1024 px)
```

## Pistes pour la suite

- Réglage de la taille du texte de lecture
