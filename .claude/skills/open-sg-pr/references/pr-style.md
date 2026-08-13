# PR title & body style (StackGuardian)

The goal: a reviewer understands **what changed, why, and what to check** without reading the diff.
Reflect and *expand* the commit messages — never just concatenate them. Professional, concise, no emojis.

## Title

Format degrades by what's available (mirrors the `com.sh` commit convention):

| Have | Title |
|---|---|
| type + ticket | `feat(SG-123): summary` |
| ticket only (type genuinely unclear) | `SG-123: summary` |
| type only | `feat: summary` |
| neither | `summary` |

Rules:
- Types are only `feat`, `fix`, `docs`.
- Imperative mood ("add", "fix", "remove" — not "added"/"adds").
- **≤ 72 characters total**, including the prefix. No trailing period.
- When a `type(...)`/`type:` prefix is present, keep the summary's first word **lowercase** (matches your commit style). With no type prefix, **Capitalize** the first word.
- The summary describes the change as a whole, not the largest file.

## Body

Use these sections in this order. **Omit any section that would be empty** — do not include a heading with "N/A" under it. If the repo has a `PULL_REQUEST_TEMPLATE.md`, use *its* structure instead and fill it with the same content.

### Summary
1–2 sentences: what this PR accomplishes, in plain language.

### Motivation & Context
Why this change is needed — the problem, the trigger, related work. Link issues here:
- `Fixes #123` when the PR closes an issue.
- `Related to #456` for context-only links.
Only include a ticket/issue reference that actually appears in the branch or commits. Do not invent one.

### Changes Made
Bullet list (`- `) of concrete, specific modifications, grouped by area when there are many. Name files/features and what happened to them. Prefer "why + what" over restating the diff line-by-line.

### Testing
Checklist of how the change was or should be validated:
- `- [x]` for checks you can see were done from the diff (e.g. tests added/updated).
- `- [ ]` for checks the reviewer or author still needs to run (manual QA, deploy smoke test).
Keep items concrete to this change; skip generic boilerplate.

### Risks & Edge Cases *(optional)*
Known limitations, behavioral changes, performance impact, backward-compat concerns. Include only if there's something real to flag.

### Deployment Notes *(optional)*
New/changed env vars, secrets, migrations, one-off commands, ordering constraints, feature flags. Include only if deployment needs a human to do something.

## Content rules
1. Lists use `- `. Task items use `- [ ]` / `- [x]`.
2. No emojis anywhere.
3. Only include URLs with concrete technical context (a specific issue, doc, or dashboard). No generic links.
4. Write in the user's voice; never signal machine authorship or add AI trailers.
5. If a **focus** hint was passed to the skill, treat it as a mandatory emphasis override — lead with and expand that aspect.

## StackGuardian specifics to watch for
When the diff touches these, call them out explicitly in **Changes Made** and, where relevant, **Deployment Notes** / **Risks**:
- GitHub Actions workflows (`.github/workflows/*.yml`) — QA vs PROD, account IDs, `@main` pins.
- `Makefile` build/deploy targets, Docker image tags/registries.
- Template files: `input_schema.json`, `ui_schema.json`, `variables.tf`, `README.md`, `DOCUMENTATION.md`.
- Workflow-step container files: `Dockerfile`, `main.sh`, step schemas.
- Anything changing AWS account IDs, regions, or secret/env wiring is a Deployment Note and usually a Risk.
