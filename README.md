## Quick Start

> [!CAUTION]
> This will install dotfiles to `$HOME`.

Using `git worktree`:
```bash
git clone --bare \
    "git@github.com:hllvc/dotfiles.git" \
    "dotfiles/.bare" && cd "dotfiles" \
    && echo "gitdir: ./.bare" > .git \
    && printf "\tfetch = +refs/heads/*:refs/remotes/origin/*" >> .bare/config \
    && git worktree add "$(git branch --show-current)" \
    && ./load.sh
```

Without `git worktree`, normal:
```bash
git clone "git@github.com:hllvc/dotfiles.git" \
    && cd "dotfiles" \
    && ./load.sh
```
