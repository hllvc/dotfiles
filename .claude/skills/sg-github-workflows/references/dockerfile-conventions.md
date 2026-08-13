# StackGuardian Dockerfile Conventions

The reusable `_build.yml` builds the repo's Dockerfile with BuildKit and
forwards repository secrets as **build secrets**. The Dockerfile must be
written to match what `_build.yml` provides. These conventions are derived
from the live `api`, `landfast-infra2code-prototype`, and
`sg-clickhouse-mcp` Dockerfiles.

## Private git dependencies — the `git_token` clone

Most SG services depend on private GitHub repos (`core`, internal libs)
installed at build time. `_build.yml` forwards **only** the `GIT_TOKEN`
repository secret, mounted as a build secret with id **`git_token`**. The
Dockerfile authenticates the clone using that token and nothing else.

### Canonical snippet

```dockerfile
RUN --mount=type=secret,id=git_token,env=GIT_TOKEN \
    git config --global url."https://${GIT_TOKEN}@github.com".insteadOf "https://github.com" && \
    <install deps that pull private repos> && \
    git config --global --unset-all url."https://${GIT_TOKEN}@github.com".insteadOf
```

### Rules

1. **Secret id is `git_token`.** It must match the `_build.yml` mount id
   exactly. Mount with `env=GIT_TOKEN` so the value lands in an env var
   scoped to that single `RUN` (no `cat /run/secrets/...` needed).
2. **Bare token in the URL** — `https://${GIT_TOKEN}@github.com`. GitHub
   accepts a PAT with no username. Do **not** add a username, do **not**
   use the `x-access-token:` prefix, and do **not** URL-encode the token
   (SG PATs are URL-safe).
3. **Never require `git_user`** (or any second clone secret). `_build.yml`
   does not forward one; a Dockerfile that reads `/run/secrets/git_user`
   will fail in CI.
4. **Rewrite `https://github.com`** (no trailing slash) via `insteadOf`,
   and **undo it** at the end of the same layer — either
   `git config --global --unset-all url.<...>.insteadOf` or
   `rm -f ~/.gitconfig` — so the credential rewrite never persists.
5. **Keep the secret in one `RUN`.** Because it's a build secret it's never
   written to image layers or visible in `docker history`; keeping the
   clone + install + unset in a single `RUN` preserves that.

### Matching workflow side

In `build_deploy_qa.yml` / `build_prod.yml`, the token is passed one of two
equivalent ways (both are accepted, don't flag either):

```yaml
    secrets:
      GIT_TOKEN: ${{ secrets.GIT_TOKEN }}   # explicit (sg-clickhouse-mcp, api)
```
```yaml
    secrets: inherit                        # inherit-all (landfast)
```

A `git_token` mount in the Dockerfile **requires** `GIT_TOKEN` in the repo
secrets and one of the two forms above. If the Dockerfile has no private
git clone, omit the secret entirely on both sides.

## General style

- **Terse comments.** One line explaining *why* a non-obvious step exists;
  no multi-paragraph essays. Match the density of the sibling Dockerfiles.
- **Clean up install-time artifacts** in the same layer they're created:
  purge `git` if it was only needed for the clone, remove apt/dnf caches
  (`rm -rf /var/lib/apt/lists/*`, `dnf clean all`), delete temp
  requirements files and the rewritten gitconfig.
- **Pin base images** to a concrete tag and use **Docker Hub by default**
  (e.g. `python:3.12-slim`). Don't reach for ECR / other registries unless
  there's a concrete reason. Builds run on GitHub-hosted runners, and pulls
  from both Docker Hub and ECR Public are anonymous (no auth) — the only
  real difference is Docker Hub's 100-pulls/6h-per-IP anonymous cap, which
  shared runner IPs can occasionally trip. If a repo's CI actually hits that
  cap, switch that image to the ECR Public mirror
  (`public.ecr.aws/docker/library/...`) — otherwise stay on Docker Hub.
- **Registry-only images:** some images have no Docker Hub home — e.g. the
  Lambda Web Adapter (`public.ecr.aws/awsguru/aws-lambda-adapter`, also on
  GHCR) and `uv` (`ghcr.io/astral-sh/uv`). Pull those from their canonical
  registry; that's a legitimate "we need it" case, not drift.
- **Lambda archetype:** copy the Lambda Web Adapter extension and set
  `PORT`/`AWS_LWA_PORT`/`AWS_LWA_INVOKE_MODE` — LWA bridges API Gateway to
  the local HTTP server.

## Other build secrets

Beyond `git_token`, `_build.yml` can forward `INFRACOST_API_KEY`,
`GH_APP_PEM_KEY_NAME(_US)`, and `GH_APP_PEM(_US)`. Each is only expected in
the Dockerfile if that Dockerfile actually mounts a matching
`--mount=type=secret,id=...`. Never flag a missing secret the Dockerfile
doesn't consume, and never flag a forwarded secret the Dockerfile does
consume.
