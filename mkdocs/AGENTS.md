# mkdocs/AGENTS.md

## Overview

Documentation site for AssetFlow, built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). Config: `mkdocs.yml` (project root). Content: `mkdocs/en/`. See `mkdocs/README.md` for setup instructions.

## Commands

Run these commands from the repository root:

```bash
uv run --group docs mkdocs serve     # Preview at http://127.0.0.1:8000
uv run --group docs mkdocs build     # Build the site in site/
uv run --group docs mike serve       # Preview deployed versions locally
```

For publishing, follow the authorized maintainer procedure in [README.md](README.md#manual-deployment).

## Site Structure

Two navbar tabs: **Home** (project landing page) and **User Guide** (all user-facing docs). Each tab has its own sidebar. Future tabs (e.g., Developer Guide) can be added as top-level nav entries in `mkdocs.yml`.

## README Sync

The repo-root `README.md` and the mkdocs home page (`mkdocs/en/index.md`) share two pieces of copy: the **Overview** description paragraph and the **Why AssetFlow?** section (intro line + bullets). When revising either, update both surfaces so they stay in sync. Treat the mkdocs version as the source of truth — the docs site is the primary user-facing surface; the README's role here is to give GitHub visitors the same pitch.

Only the English copy is mirrored to the README. The Chinese version (`mkdocs/zh-TW/index.md`) is updated separately whenever the pitch wording changes.

## i18n

Uses `mkdocs-static-i18n` with folder-based layout. English: `mkdocs/en/`. Chinese (Taiwanese): `mkdocs/zh-TW/` (mirrors `en/` structure). Screenshots in `mkdocs/assets/images/` are shared across languages.

To add a language: create the folder, add the locale to `mkdocs.yml > plugins > i18n > languages`.

### Non-Latin headings and search

`mkdocs.yml` configures the `toc` extension with `pymdownx.slugs.slugify` (`case: lower`, `percent_encode: true`) so non-Latin headings (e.g., Chinese) produce stable percent-encoded anchor IDs that match `[text](page.md#編碼後的錨點)` links. Without this, Python-Markdown's default slugify strips non-ASCII characters and headings collapse to numeric IDs (`_1`, `_2`, …), breaking cross-page anchor links.

`plugins.search.lang` is set to `[en, zh]` so lunr loads `lunr.zh.min.js` for Chinese tokenization. The `mkdocs-static-i18n` plugin can't auto-map locale `zh-TW` → lunr language `zh`, so on every build you'll see this informational message — leave it as-is:

```
INFO - mkdocs_static_i18n: Language 'zh-TW' is not supported by lunr.js, not setting it in the 'plugins.search.lang' option
```

Silencing it would require `reconfigure_search: false`, which also disables the plugin's cross-language search-index dedup — a worse tradeoff. When adding a locale whose primary language *is* in lunr (e.g., `zh-CN`, `ja-JP`), add the language code (`zh`, `ja`) to `plugins.search.lang` manually.

## Build Hooks

Custom MkDocs hooks live in `mkdocs/hooks/`, registered under `hooks:` in `mkdocs.yml` and excluded from the site output via `exclude_docs: hooks/`.

- `mkdocs/hooks/include_revision_date.py` — for pages that consist only of an `{% include-markdown "<path>" %}` directive (e.g., `mkdocs/en/user-guide/changelog.md` pulls in the repo-root `CHANGELOG.md`), this hook re-runs `mkdocs-git-revision-date-localized-plugin` against the included file so the "Last update" / "Created" footer reflects the real source history instead of the rarely-touched include stub.

## Theme Overrides

Material for MkDocs theme overrides live in `overrides/` (at the repo root, outside `docs_dir`). Config: `theme.custom_dir` in `mkdocs.yml`.

Current overrides:

- `partials/alternate.html` — fixes the language switcher on home pages for mike versioning. The `mkdocs-static-i18n` plugin generates absolute links for home pages, which bypass mike's version subdirectory. The override rewrites them as relative links. This template assumes the default language is listed first in the `i18n > languages` config.

## Versioning

Uses [mike](https://github.com/jimporter/mike) for multi-version docs. Config: `extra.version` in `mkdocs.yml`. CI deploys `dev` on pushes to `main` and a tagged version on each GitHub release (see `.github/workflows/docs.yml`). The `latest` alias always points to the most recent release. Do not use `mkdocs gh-deploy` directly; always deploy through mike.

## Images

- Screenshots stored in `mkdocs/assets/images/` and tracked by **Git LFS** (configured in `.gitattributes`)
- Install Git LFS and run `git lfs install`; in an existing checkout, run `git lfs pull` to fetch image content
- Reference images from content pages with relative paths (e.g., `../../assets/images/app-overview.png` from `guide/` pages)

## Writing Conventions

- **Audience**: End users, not developers. Friendly, clear tone.
- **Em-dashes**: Avoid in repetitive patterns (e.g., "See also" link lists). Use colons instead: `- [Page](link.md): Description`. Em-dashes in prose are fine when they sound natural.
- **Ordered lists**: Use `1.` for all items (same as project-wide convention).
- **Keyboard shortcuts**: Use `pymdownx.keys` syntax: `++cmd+n++`, `++cmd+comma++`.
- **Admonitions**: Use `!!! tip`, `!!! note`, `!!! warning` for callouts. Leave a blank line after the `!!!` directive.
- **Settings navigation**: Settings is a macOS settings window (++cmd+comma++), not in the sidebar. Write "Open **Settings** (++cmd+comma++)" not "Go to Settings in the sidebar."
- **Cross-references**: Every page ends with a "See also" section linking to related pages.
- **No duplication**: Cash flows page covers workflow; performance metrics covers the math. Charts are covered inline in each feature page, not as a standalone page. Import CSV covers workflow; reference/csv-format covers the spec.

## Required Extensions

Grid cards on the home page require `md_in_html`. Material icons (`:material-camera:`) require `pymdownx.emoji`. Both are configured in `mkdocs.yml`. If adding new markdown features, ensure the required extension is listed.

## Formatting

MkDocs content uses a separate `mdformat` pre-commit hook (`mdformat-mkdocs` + `mdformat-front-matters` + `mdformat-simple-breaks`) instead of the project-wide `mdformat-gfm`. This preserves Material for MkDocs syntax (frontmatter, admonitions, grid card `---` separators) that standard mdformat would break.

## Verifying Changes

```bash
uv run --group docs mkdocs build
```

Inspect the build output. Warnings about missing images are expected if screenshots have not been added yet; broken links or missing pages need correction.
