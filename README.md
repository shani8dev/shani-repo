# shani-repo

The published pacman package repository for Shanios, served via GitHub Pages
at the custom domain `repo.shani.dev` (see `CNAME`). Mostly generated
output — package archives and the `.db`/`.files` databases — produced by
[`shani-builder`'s `pkg-builder.sh`](https://github.com/shani8dev/shani-builder)
build/sign/publish pipeline. Not hand-edited: changes originate in
`shani-builder`, not here.

## Adding the repo to a client

Add the following to your `pacman.conf` — this is exactly what Shanios's
own images ship in `/etc/pacman.conf`:

```ini
[shani]
Server = https://repo.shani.dev/$arch
```

`SigLevel` doesn't need to be set per-repo here — it inherits the global
`[options]` default (`Required DatabaseOptional`), which requires valid
package signatures. On a non-Shanios Arch system, trust the signing key
first (packages in this repo are signed with it, so pacman needs it before
it will install anything from `[shani]` — including `shani-keyring` itself):

```bash
sudo pacman-key --recv-key 7B927BFFD4A9EAAA8B666B77DE217F3DA8014792 --keyserver keys.openpgp.org
sudo pacman-key --lsign-key 7B927BFFD4A9EAAA8B666B77DE217F3DA8014792
```

Refresh the package database and install the keyring before installing
anything from this repo:

```bash
sudo pacman -Sy
sudo pacman -S shani-keyring
```

(Shanios itself ships with this repo and key already configured — nothing
to do there.)

## Architecture

This repo currently serves `x86_64` packages only. No other architecture
directories exist; if shani targets ARM/aarch64 in the future, this repo
would need a parallel architecture tree.

The database is signed with the project signing key
(`7B927BFFD4A9EAAA8B666B77DE217F3DA8014792`), and every `.sig` under
`x86_64/` is verified against it on every push/PR by
`.github/workflows/ci.yml`'s `check-repo-integrity.sh`.

## How packages get here

`shani-builder/pkg/pkg-builder.sh`:
1. Clones `shani-pkgbuilds` (the PKGBUILD sources) and this repo.
2. For each PKGBUILD, skips if the built package + signature already exist,
   otherwise builds inside the `shani-builder` Docker container.
3. Signs each package with `gpg --detach-sign`.
4. Moves the built `.pkg.tar.zst` and `.sig` into the architecture directory.
5. Removes old versions whose name/version/release no longer match.
6. Runs `repo-add` to regenerate `shani.db` and `shani.files`.
7. Commits and pushes back to this repo via SSH.

## Trust rules

- **A `.sig` is not self-contained.** It's only valid paired with the exact
  `.db`/`.files` bytes it was generated against. `git merge` has no concept
  of that relationship — a merge that takes a newer database from one branch
  and a stale `.sig` from another produces a present-but-invalid signature,
  which is a hard failure under `SigLevel = Required DatabaseOptional`
  (a missing signature is merely tolerated). Never manually merge a
  locally-regenerated `.sig`/`.db` pair against `origin`; let the next real
  CI publish regenerate both together, or re-verify `gpg --verify` against
  the post-merge files before pushing.
- **Never commit anything that isn't meant to be public.** Everything in this
  repo is served to the public internet unauthenticated. Before adding any
  file, double-check it isn't a private key, a credential, or a leaked build
  artifact.

## Cross-repo impact

This repo's output is published by `shani-builder/pkg/pkg-builder.sh`
(**not** `shani-pkgbuilds` — that repo only holds the PKGBUILD sources
packages get built from) and consumed by every real Shanios install's
`pacman.conf`. If you change anything about how the database is signed or
structured, confirm `pkg-builder.sh`'s `rebuild_database()` still produces
something this repo (and real pacman clients) accept — don't assume
compatibility, check it.