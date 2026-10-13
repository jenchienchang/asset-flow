# Documentation Editing Guidelines

These instructions apply to maintained documentation in this directory and supplement the repository-level agent instructions. Read [README.md](README.md) before editing; it defines each document's purpose, audience, and ownership boundaries.

## Conciseness and a Single Source of Truth

Conciseness is essential for readability and maintaining a single source of truth. Evaluate each detail from the perspective of the whole documentation set, not just the file being edited.

- Keep the context, rules, contracts, constraints, examples, and rationale needed to answer the document's primary question.
- Put each detailed definition in its owning document. Use short contextual summaries and cross-links elsewhere.
- Do not blindly include every related fact or remove every overlapping topic. Some context is necessary for a document to be understandable on its own.
- Before removing or relocating essential information, verify that the owning document retains it and readers can find it. Coordinate changes across documents without losing information between edits.
- Preserve useful project-specific content. Remove repetition, incidental implementation details, stale inventories, and patch-history narration. Conciseness is not an arbitrary word or line limit.

## Scope and Ownership

- Follow README's document responsibilities. Keep SPEC focused on product requirements, design documents on their respective decisions and contracts, and README on scope and navigation.
- Keep contributor procedures in DevelopmentGuide, conventions in CodeStyle, and verification design in TestingStrategy. Link to repository configuration and source rather than copying exhaustive rules or symbol inventories.
- Separate Swift application development from Python repository tooling within DevelopmentGuide and TestingStrategy. Keep shared prerequisites and contributor workflows together; group any Python conventions separately in CodeStyle.
- Architecture describes the shipped application. Include repository tooling there only when it affects application architecture.
- User-facing instructions belong in `mkdocs/`; source-level model orientation belongs in `AssetFlow/Models/README.md`. Review related material for consistency without expanding the authorized editing scope.
- When assigned one document, report necessary changes to other owners rather than editing their files. When authorized to update several documents, keep the related definitions and links consistent.

## Correctness and Evidence

- Verify behavior, fields, signatures, formats, defaults, dependencies, and commands against relevant source, tests, configuration, and repository instructions. Existing prose alone is not sufficient evidence.
- SPEC is the source of truth for intended product behavior. When asked to synchronize documentation with the current repository, correct stale descriptions using implementation evidence. Otherwise, identify a requirement/implementation discrepancy explicitly rather than silently changing the requirement or code.
- A documentation assignment does not authorize implementation changes. Report concerns requiring code changes separately and continue independent documentation corrections.
- Distinguish implemented behavior, requirements, proposals, and known limitations. Qualify or omit unsupported claims; do not invent behavior to fill a documentation gap.
- Use primary sources for uncertain framework, platform, mathematical, security, or privacy claims. Cite supporting references near the relevant explanation.
- Do not claim completeness, compliance, encryption, secure erasure, signing, or test coverage beyond the evidence. Distinguish automated assertions, source checks, rendered samples, and interactive verification.

## Writing and Examples

- Lead with the purpose or behavior, define terms before using them, and use short connected explanations. Use tables for comparisons and lists for genuinely parallel or sequential information.
- Consolidate feature additions into the relevant sections instead of accumulating appendices. Preserve important invariants and decision rationale.
- Clearly distinguish zero, absent, invalid, unavailable, and stale values. State financial units, cash-flow signs, date boundaries, precision, and rounding where needed; link to the authoritative definitions.
- Keep examples small and meaningful. Executable examples must use actual interfaces, correct actor context, Decimal financial values, valid CSV, and current project conventions. Label pseudocode explicitly.
- Commands must identify their working directory, prerequisites, and relevant effects. Distinguish human/CI procedures from agent execution and approval rules; examples do not grant authorization.
- Use `1.` for every ordered-list item. Do not manually align Markdown table columns or run formatting/linting after edits; pre-commit hooks handle them.

## Completion Checks

1. Review the change for correctness, readability, necessary context, ownership, and duplication across related documents.
1. Check relative links, heading anchors, source references, and examples. Search for consumers before renumbering SPEC sections or moving referenced content; update affected links within scope or report followups.
1. Update README when adding a document or changing document responsibilities.
1. Use verification proportional to the change. Prose-only edits normally need link/example checks, not an app build or full test suite. If compilation or tests are necessary, follow the repository build/test instructions and skills.
1. Report what changed, what was verified, and any remaining factual uncertainties or followups. Do not claim checks passed unless they were performed and their results inspected.
