# PR title & body style (StackGuardian)

The goal: a reviewer understands **what changed, why, and what to check** in under a minute.
Summarize the commits — do not restate them one by one, and do not expand them. Professional,
concise, no emojis.

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

**Length budget: 150–250 words for a normal PR.** Go beyond that only when the diff is genuinely
large (many areas or a migration), and even then stay under ~400 words. A small PR (one or two
commits, a handful of files) should fit in Summary + Changes with a short Testing list.

Use these sections in this order. **Omit any section that would be empty** — never add a heading
with "N/A" under it. If the repo has a `PULL_REQUEST_TEMPLATE.md`, use *its* structure instead and
fill it with the same content, under the same budget.

### Summary
One short paragraph (2–4 sentences): what this PR does and why it's needed — the problem or trigger.
Put issue links here:
- `Fixes #123` when the PR closes an issue.
- `Related to #456` for context-only links.
Only reference a ticket/issue that actually appears in the branch or commits. Do not invent one.

### Changes
**5–8 bullets max**, grouped by area (e.g. "CI", "Makefile", "Template schema"), not by file.
Each bullet says what changed and, when not obvious, why. Mention a file only when the reviewer
must open it — never list every touched file; the diff already does that.

### Testing
**3–4 items max.** Only checks that are specific to this change:
- `- [x]` for checks visibly done in the diff (tests added/updated, CI passing).
- `- [ ]` for checks the reviewer or author still needs to run (manual QA, deploy smoke test).
Omit the section entirely if there is nothing concrete to list — do not invent reviewer tasks.

### Risks *(optional)*
Behavioral changes, backward-compat concerns, performance impact. Include only if there's
something real to flag, and keep it to 1–3 bullets.

### Deployment Notes *(optional)*
New/changed env vars, secrets, migrations, one-off commands, ordering constraints, feature flags.
Include only if deployment needs a human to do something.

## Content rules
1. Lists use `- `. Task items use `- [ ]` / `- [x]`.
2. No emojis anywhere.
3. Only include URLs with concrete technical context (a specific issue, doc, or dashboard). No generic links.
4. Write in the user's voice; never signal machine authorship or add AI trailers.
5. If a **focus** hint was passed to the skill, treat it as a mandatory emphasis override — lead with and expand that aspect, and cut elsewhere to stay within budget.
6. **Say each fact once.** A change belongs in the single most relevant section; do not repeat it across Changes, Risks, and Deployment Notes.

## StackGuardian specifics to watch for
When the diff touches these, make sure they're mentioned — once, in whichever section fits best:
- GitHub Actions workflows (`.github/workflows/*.yml`) — QA vs PROD, account IDs, `@main` pins.
- `Makefile` build/deploy targets, Docker image tags/registries.
- Template files: `input_schema.json`, `ui_schema.json`, `variables.tf`, `README.md`, `DOCUMENTATION.md`.
- Workflow-step container files: `Dockerfile`, `main.sh`, step schemas.
- Anything changing AWS account IDs, regions, or secret/env wiring goes in Deployment Notes (and Risks only if it can break something).
