# Documentation Site

This directory contains the source files for the [AssetFlow documentation site](https://jenchienchang.github.io/asset-flow/), built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).

## Prerequisites

- Python from the repository's [`.python-version`](../.python-version) (currently 3.12)
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

# Install the documentation dependency group in the project-local .venv
uv sync --locked --group docs
```

## Local Development

From the repository root, after installing the `docs` group:

```bash
# Start the live-reloading dev server
uv run --locked --group docs mkdocs serve

# Build the static site (output: site/)
uv run --locked --group docs mkdocs build
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
│   ├── images/                 # Screenshots shared across languages (Git LFS)
│   └── stylesheets/
│       └── extra.css           # Shared screenshot layout
└── README.md                   # This file

overrides/                      # Material theme overrides (custom_dir, at repo root)
└── partials/
    └── alternate.html          # Language switcher fix for mike versioning
```

## Adding or Updating Screenshots

Screenshots in `assets/images/` are tracked by Git LFS. Simply add or replace `.png` files as usual. Git LFS handles the rest transparently.

### Screenshot layout

`assets/stylesheets/extra.css`, registered through `extra_css` in `mkdocs.yml`, centers standalone screenshots within the text column in both languages. Images retain their natural size and scale down to fit narrower screens. The rule targets image-only paragraphs containing screenshots from `assets/images/`, excluding explicitly aligned images; theme icons and the navigation logo are unaffected.

Introduce each screenshot with text explaining what to look for. Separate screenshots of different views with relevant explanations or subsections rather than placing them back-to-back. Keep the structure consistent in English and Traditional Chinese.

### Capture and review

Use disposable data when capturing portfolio screens. Review each image against the current interface for labels, values, layout, and visible private data. Capture help popovers and confirmation dialogs with enough of the surrounding window to show their context; a rendered view sample does not verify how a native control opens.

Keep English and Traditional Chinese screenshots aligned where the interface text differs. Update page references when replacing an image, and remove superseded files after checking that no page uses them. The pages themselves are the source of truth for which screenshots are currently needed.

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

These commands publish changes to remote Git state. Run them only for an authorized maintainer release, from the repository root with the `docs` group installed.

```bash
# Deploy a specific version with the "latest" alias
uv run --locked --group docs mike deploy --push --update-aliases v1.0.0 latest

# Set the default redirect (root URL → latest)
uv run --locked --group docs mike set-default --push latest

# Preview all deployed versions locally
uv run --locked --group docs mike serve
```
