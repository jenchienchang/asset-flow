---
name: commit
description: Use when the user asks Codex to prepare a commit from staged changes; show the full conventional commit message and wait for approval before committing.
---

# Commit Staged Changes

Commit only the changes that are already staged, and only after the user approves the exact proposed commit message.

## Workflow

1. Inspect the staged change set:

   ```bash
   git status --short
   git diff --cached --stat
   git diff --cached
   ```

1. If nothing is staged, stop and tell the user there are no staged changes to commit.

1. Draft a concise conventional commit message:

   - Format: `<type>[optional (scope)][!]: <subject>`. If included, put the scope in parentheses.
   - Use the repository's allowed types from `AGENTS.md`.
   - Mark a breaking change with `!` after the type or scope, or include a `BREAKING CHANGE: <description>` footer.
   - Use a lowercase subject. Write the body in sentence case and end it with a period.
   - Include a body in every commit, explaining the motivation and summarizing meaningful included changes.
   - Wrap body paragraphs, bullets, and footer lines so each line is 72 characters or fewer.
   - If the user supplied a rationale, incorporate it as the "why".
   - Describe the concept-level purpose and list meaningful included changes.
   - Do not describe the iterative workflow of implementation, review, or revision.

1. Show the complete proposed commit message, including the subject and entire body, to the user in a code block. Stop and wait for explicit approval of that exact message. The initial request to commit authorizes preparation only; it does not authorize running `git commit`.

1. After approval, run `git commit` with exactly the approved message so the repository's pre-commit hooks can review the commit. Do not stage or unstage files, and do not include changes that were not already staged. Never use `--no-verify` (or any equivalent option) to bypass the hooks.

1. Treat the pre-commit result as authoritative:

   - If all hooks pass and the commit succeeds, report the resulting commit hash and subject.
   - If a hook fails or prevents the commit, stop. Report the hook result and any relevant status or diff, and wait for the user to address it. Do not bypass the hook, retry with verification disabled, or continue as if the commit succeeded. If hooks modified files, mention that those changes may need review and staging by the user.

## Message Shape

Use this shape for every generated commit:

```text
<type>[optional (scope)][!]: <subject>

<Why this change is being made, wrapped to 72 columns.>

- <Included change, wrapped to 72 columns.>
- <Another included change.>

BREAKING CHANGE: <Description, when applicable>
```

Every generated commit message must include a body. Body paragraphs and bullets must use sentence case, and the body must end with a period. Wrap body and footer lines so no individual line exceeds 72 characters.
