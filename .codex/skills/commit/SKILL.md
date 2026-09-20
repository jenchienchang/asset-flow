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

   - Format: `<type>(<scope>): <subject>`
   - Use the repository's allowed types from `AGENTS.md`.
   - Include a body in every commit, explaining the motivation and summarizing meaningful included changes.
   - In the generated commit message, wrap long body paragraphs or bullets onto continuation lines so each commit-message body line is 72 characters or fewer.
   - If the user supplied a rationale, incorporate it as the "why".
   - Describe the concept-level purpose and list meaningful included changes.
   - Do not describe the iterative workflow of implementation, review, or revision.

1. Show the complete proposed commit message, including the subject and entire body, to the user in a code block. Stop and wait for explicit approval of that exact message. The initial request to commit authorizes preparation only; it does not authorize running `git commit`.

1. After approval, run `git commit` with exactly the approved message so the repository's pre-commit hooks can review the commit. Do not stage or unstage files, and do not include changes that were not already staged. Never use `--no-verify` (or any equivalent option) to bypass the hooks.

1. Treat the pre-commit result as authoritative:

   - If all hooks pass and the commit succeeds, report the resulting commit hash and subject.
   - If a hook fails or prevents the commit, stop. Report the hook result and any relevant status or diff, and wait for the user to address it. Do not bypass the hook, retry with verification disabled, or continue as if the commit succeeded. If hooks modified files, mention that those changes may need review and staging by the user.

## Message Shape

Use this shape when a body is warranted:

```text
<type>(<scope>): <subject>

<why this change is being made, wrapping long text onto continuation lines>

- <included change, wrapping long text onto continuation lines>
- <included change>
```

Every generated commit message must include a body. Body paragraphs and bullets may contain more than 72 characters of content, but split them across multiple commit-message lines so no individual body line exceeds 72 characters.
