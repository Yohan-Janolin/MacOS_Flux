<p align="center">
  <img src="Design/Flux-icon.svg" width="128" alt="Flux icon" />
</p>

<h1 align="center">Flux</h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1-FF6A3D" alt="Version 0.1" />
  <img src="https://img.shields.io/badge/macOS-14%2B-1C1B33?logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-60A5FA" alt="Universal app" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2DD4BF" alt="MIT License" /></a>
</p>

<p align="center">
  🇬🇧 English · <a href="README.fr.md">🇫🇷 Français</a>
</p>

---

Flux is a simple, good-looking RSS reader for macOS.

You add your feeds yourself (no directory, no account, no recommendations), you browse the articles as a list with thumbnails or as a grid, and you read the **full article right inside the app**, without opening your browser. Everything stays on your Mac.

Flux is a native SwiftUI app, available in English and French, in light and dark mode.

<!--
## 📸 Screenshots

<p align="center">
  <img src="docs/screenshots/main.png" width="800" alt="Flux main window" />
</p>

| List | Thumbnails | Settings |
|:---:|:---:|:---:|
| <img src="docs/screenshots/list.png" width="260" alt="List view" /> | <img src="docs/screenshots/grid.png" width="260" alt="Thumbnail view" /> | <img src="docs/screenshots/settings.png" width="260" alt="Settings" /> |
-->

## ✨ Features

### 📰 Your feeds, your way

- **Add a feed** (⌘N) by pasting its address, or simply the website's address: Flux finds the feed declared by the site, then tries the usual paths (`/feed`, `/rss`, `/atom.xml`…).
- **Folders** (⇧⌘N), collapsible, with their own unread count, color and icon (right-click › Customize…). Drag a feed onto a folder to file it.
- **Rename a feed** (right-click › Rename…) when its name is too long. The original name is kept, so you can go back to it.
- **OPML import and export** (File menu, ⇧⌘I / ⇧⌘E) to bring your subscriptions from another reader (NetNewsWire, Reeder, Feedly…) with their folders, or to back them up.
- **Limitations:** nested folders in an OPML file are flattened to their closest folder.

### 🖼️ A list you enjoy browsing

- **List** view with a thumbnail, the source, the date, the title and an optional summary, or **Thumbnails** view (a grid of images with the title underneath). Switch between them in the toolbar.
- Thumbnails come from the feed (`media:thumbnail`, `enclosure`…), from the first image of the article, or as a last resort from the page's `og:image`.
- **Search** in the title and full text of the articles of the current view.
- **Multiple selection** (⌘-click, ⇧-click, ⇧↑/↓, ⌘A) to mark several articles as read, unread or favorite at once.

### 📖 The full article, in the app

- When a feed only provides an excerpt (short, or cut with “…” or “Read more”), Flux downloads the page and extracts the article with [Readability.js](https://github.com/mozilla/readability), the engine behind Firefox's Reader View. A button switches between the feed version and the full article.
- Clean reading layout, light or dark, with three text widths (narrow, wide, full width). Links open in your default browser.
- **Limitations:** articles reserved for a site's subscribers stay cut, since the site itself doesn't serve the rest. Pages built entirely in JavaScript can be extracted poorly: the “Open in Browser” button is there for those.

### ⌨️ Keyboard shortcuts, Reeder style

| Key | Action |
|---|---|
| j / k | Next / previous article |
| Space / ⇧ Space | Scroll the article (at the bottom: next article) |
| m | Mark as read / unread (whole selection) |
| s | Add to / remove from favorites (whole selection) |
| b | Open in browser |
| ↑ / ↓ (← / → in Thumbnails) | Move in the list; with ⇧, extend the selection |
| ⌘N / ⇧⌘N | Add a feed / new folder |
| ⌘R | Refresh |
| ⇧⌘K | Mark all as read (current view) |
| ⌘, | Settings |

Single-key shortcuts are ignored while you type in a text field.

### ✈️ Offline reading

When enabled (Settings › Offline), after each refresh Flux downloads unread articles and favorites in full, **images included**, so you can read them without a connection. Without a connection, the toolbar shows “Offline”.

- The image cache has a size limit (250 MB to 5 GB, 1 GB by default); the least recently used images are removed first. Its size is shown in Settings, with a button to clear it.
- **Limitations:** up to 25 images per article. The first preparation can take a few minutes if you have many unread articles.

### ⭐ Favorites, read status and cleanup

- **Favorites** are kept forever, even once read, and are never marked as read automatically.
- **Mark articles as read** immediately, after 5, 10 or 30 seconds, or never (Settings › Reading).
- Optionally **mark old articles as read** after 1 day to 1 month, with a preview of how many articles are affected before you apply.
- Read articles that aren't favorites are **deleted** after 2 weeks to 1 year (2 months by default).
- **Limitation:** deleting a feed also deletes its articles, favorites included.

### ⚙️ Settings

Appearance (automatic, light, dark), language (system, English, French), summary under the title, article text width, mark-as-read delay, refresh interval (15 minutes to 6 hours), offline reading and storage.

## 🧩 Compatibility

**macOS 14 (Sonoma) or later**, on Apple Silicon and Intel Macs.

Feed formats: **RSS 2.0**, **RSS 1.0 (RDF)**, **Atom** and **JSON Feed**, served over `https` or `http`.

## 🔐 Required permissions

None. Flux needs no special permission: it only uses the network to download your feeds, their articles and their images.

## 🔒 Privacy

Flux collects nothing and sends nothing about you. There is no account, no analytics and no tracking. The only network requests go directly to the sites you subscribe to: their feeds, the pages of their articles, their images and their favicons. Everything is stored on your Mac:

- articles, feeds and folders: `~/Library/Application Support/Flux/Flux.store`;
- image cache: `~/Library/Application Support/Flux/Images`.

## 📥 Installation

There's no downloadable version yet: for now, Flux is built from source (see below). It takes a couple of minutes with Xcode.

## 📝 Changelog

### 0.1
- First version: manual feeds and folders, list and thumbnail views, full article reading with Readability, search, multiple selection, Reeder-style shortcuts, offline reading, OPML import/export, settings, English and French, light and dark mode.

## 🛠️ Building from source

Requirements: Xcode 15 or later, macOS 14 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the Xcode project is generated from `project.yml`).

```bash
brew install xcodegen
git clone https://github.com/Aervorn/MacOS_Flux.git
cd MacOS_Flux
xcodegen generate
open Flux.xcodeproj
```

Choose the **Flux** scheme and **My Mac**, then **Product › Run** (⌘R). The project is set to **Sign to Run Locally**: no Apple developer account is needed.

After a `git pull` that adds or removes files, run `xcodegen generate` again.

```
Flux/
├── FluxApp.swift          entry point, SwiftData database, windows and menus
├── Models.swift           Feed, Folder, Article
├── FeedParser.swift       RSS / Atom parser and dates
├── FeedStore.swift        adding, refreshing, offline preparation, OPML, cleanup
├── ArticleExtractor.swift Readability.js in a hidden WKWebView
├── ImageCache.swift       disk image cache, flux-image:// protocol, thumbnails
├── HTMLUtils.swift        plain text, entities, images, feed discovery
├── OPML.swift             OPML import / export
├── Keyboard.swift         single-key shortcuts
├── Settings.swift         settings, appearance, language
├── Views/                 SwiftUI interface
├── en.lproj / fr.lproj    translations
└── Resources/Readability.js
Design/                    app icon (SVG, and the Python script that generates the PNGs)
```

## 🤝 Contributing & issues

Bug reports, ideas and pull requests are welcome!

- **A feed that doesn't load properly?** [Open an issue](https://github.com/Aervorn/MacOS_Flux/issues/new) with the feed's address, your macOS version, what you expected and what happened. A screenshot helps a lot.
- **An idea?** Open an issue to discuss it first.
- **A pull request?** Keep it focused on one change. The interface texts are written in French in the code; add the English translation of any new text in `Flux/en.lproj/Localizable.strings`.

## ⚠️ Disclaimer

Flux is provided **“as is”, without any warranty**. The author can't be held responsible for any data loss or other damage. Use it at your own risk.

Flux isn't affiliated with the sites whose feeds you read. Articles, images and logos belong to their respective authors.

## 📄 License

Flux is released under the [MIT License](LICENSE).

Article extraction uses [Readability.js](https://github.com/mozilla/readability) by Mozilla, released under the Apache 2.0 License (see `Flux/Resources/Readability-LICENSE.md`).
