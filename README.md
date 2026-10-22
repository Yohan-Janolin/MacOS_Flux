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
- **Dossiers** (⇧⌘N) : repliables, avec le total des non-lus. Range un flux en
  le glissant sur un dossier, ou via clic droit › Déplacer vers. Glisser un flux
  sur l'en-tête « Flux » le sort de son dossier. Supprimer un dossier ne supprime
  pas ses flux.
- **Actualisation** : au lancement, toutes les 30 minutes, et avec ⌘R.
- **Nettoyage** : les articles lus et non favoris de plus de 60 jours sont
  supprimés.
- **Données** : `~/Library/Application Support/Flux/Flux.store` (SwiftData).

## Raccourcis

| Raccourci | Action |
|---|---|
| ⌘N | Ajouter un flux |
| ⇧⌘N | Nouveau dossier |
| ⌘R | Actualiser |
| ⇧⌘K | Tout marquer comme lu (dans la vue courante) |
| ↑ / ↓ | Naviguer dans la liste |

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
├── Views/                 interface SwiftUI
└── Resources/Readability.js
```

## Pistes pour la suite

- Import/export OPML
- Recherche dans les articles
- Raccourcis clavier façon Reeder (j/k, espace pour défiler, m pour lu/non lu)
- Réglages : intervalle d'actualisation, durée de rétention, taille du texte
