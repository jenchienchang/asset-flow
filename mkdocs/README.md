# Documentation Site

This directory contains the source files for the [AssetFlow documentation site](https://jenchienchang.github.io/asset-flow/), built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).

## Prerequisites

- [Python 3.11+](https://www.python.org/)
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- [Git LFS](https://git-lfs.com/) (for screenshot images)

## Setup

From the repository root:

```bash
# Install Git LFS (if not already installed)
brew install git-lfs
git lfs install

# Pull LFS files (if cloning for the first time)
git lfs pull

# Install Python dependencies
uv sync
```

## Local Development

```bash
# Start the live-reloading dev server
uv run mkdocs serve

# Build the static site (output: site/)
uv run mkdocs build
```

The dev server runs at `http://127.0.0.1:8000` and automatically reloads when you edit any file.

## Directory Structure

```
mkdocs/                         # docs_dir (content source)
├── en/                         # English content (default language)
│   ├── index.md                # Home page
│   └── user-guide/             # User Guide tab
│       ├── index.md
│       ├── getting-started/
│       ├── guide/
│       ├── settings/
│       ├── reference/
│       ├── faq.md
│       ├── troubleshooting.md
│       └── changelog.md
├── zh-TW/                      # Chinese (Taiwanese), mirrors en/ structure
├── assets/
│   └── images/                 # Screenshots shared across languages (Git LFS)
└── README.md                   # This file

overrides/                      # Material theme overrides (custom_dir, at repo root)
└── partials/
    └── alternate.html          # Language switcher fix for mike versioning
```

## Adding or Updating Screenshots

Screenshots in `assets/images/` are tracked by Git LFS. Simply add or replace `.png` files as usual. Git LFS handles the rest transparently.

## Adding a New Language

The site uses [mkdocs-static-i18n](https://github.com/ultrabug/mkdocs-static-i18n) with a folder-based layout. To add a new language:

1. Create a new folder under `mkdocs/` (e.g., `mkdocs/zh-TW/`) mirroring the `en/` structure.
1. Add the locale to `mkdocs.yml` under `plugins > i18n > languages`.
1. If the language is supported by [lunr.js](https://lunrjs.com/) but the locale code isn't (e.g., `zh-TW` → `zh`), add the language code to `plugins > search > lang` so search uses the correct tokenizer.
1. Translate the content. Screenshots in `assets/images/` are shared across all languages.

### Note on the `lunr.js` build message

When building the site, `mkdocs-static-i18n` emits an informational message for any locale not directly recognized by lunr.js:

```
INFO - mkdocs_static_i18n: Language 'zh-TW' is not supported by lunr.js, not setting it in the 'plugins.search.lang' option
```

This is expected and harmless. The plugin's auto-detector compares the literal locale string (e.g., `zh-TW`) against lunr's supported languages and can't fall back to the parent language code (`zh`). We've already mapped this manually via `plugins.search.lang: [en, zh]` in `mkdocs.yml`, so Chinese tokenization works correctly. Silencing the message would require disabling the plugin's `reconfigure_search` step, which also turns off cross-language search-index deduplication.

## Versioning

The site uses [mike](https://github.com/jimporter/mike) for version switching. Each release tag gets its own version, and a `latest` alias always points to the most recent release.

- **Automatic deployment**: The `docs.yml` GitHub Actions workflow deploys `dev` on pushes to `main` (when docs change) and a versioned snapshot on each release.
- **Version selector**: A dropdown in the header lets readers switch between versions.

### Manual deployment

```bash
# Deploy a specific version with the "latest" alias
uv run mike deploy --push --update-aliases v1.0.0 latest

# Set the default redirect (root URL → latest)
uv run mike set-default --push latest

# Preview all deployed versions locally
uv run mike serve
```
