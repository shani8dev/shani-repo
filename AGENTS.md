# Agent instructions — shani-repo

This file applies to any AI coding assistant working in this repository
(Claude Code, opencode, Kilo Code, Cursor, Aider, or similar). Read this
before editing, and follow the verification steps before calling any change
done.

## What this repo is

The published pacman package repository for Shanios, served via GitHub
Pages at `repo.shani.dev`. Mostly generated/published output (package
archives, `.db`/`.files` databases), not hand-authored source — most
"changes" here come from a publish step elsewhere
(`shani-builder/pkg/pkg-builder.sh`'s `build_package()`/
`rebuild_database()` — not `shani-pkgbuilds`, which only holds the
PKGBUILD sources these get built from; verified via
`grep -rln "repo-add" **/*.sh` across the whole ecosystem, since an
earlier version of this file pointed at the wrong repo), not direct edits.

## Rule: verify what actually gets served, not just what's committed

Before considering a change here done:

```bash
# The database itself must be parseable and match what pacman expects
tar -tzf x86_64/shani.db.tar.gz | head    # or shani.db, depending on current naming
```

If you or a build step add/modify a `.sig` file, confirm it actually
verifies against the real signing key (see `shani-keyring`) — a `.sig`
that doesn't verify is worse than no `.sig`, since client tooling may
treat its mere presence as a signal the repo is signed.

**Never commit anything that isn't meant to be public** — everything in
this repo is served to the public internet unauthenticated. Before adding
any file, double-check it isn't a private key, a credential, or a
temp/build artifact that leaked in from a build step.

## Rule: a `git merge` here can silently break the database's signature

A `.sig` file is not a self-contained fact — it's only valid paired with the
exact `.db`/`.files` bytes it was generated against, but `git merge` has no
concept of that relationship. If a branch changed the database (a real CI
rebuild) and another branch changed only the `.sig` (a local re-sign), a
plain `git merge` happily takes each file from whichever side touched it —
producing a `.sig` that doesn't match its neighboring `.db`, which is worse
than no `.sig` at all under `SigLevel = Required DatabaseOptional` (a
present-but-invalid signature is a hard failure; a missing one is
tolerated). This isn't hypothetical — see the incident below. Prefer never
manually merging a locally-regenerated `.sig`/`.db` pair against `origin`;
let the next real CI publish regenerate both together instead, or at minimum
re-verify `gpg --verify` against the post-merge files before pushing, not
just the pre-merge ones.

## If you have Superpowers / oh-my-opencode / ultrawork / similar available

If your environment provides Claude Code's **Superpowers** plugin, OpenCode's
**oh-my-opencode**, an **ultrawork**-style parallel execution mode, or an
equivalent skill/subagent framework — use it to verify multiple packages'
`.sig` files against the real signing key concurrently rather than one at a
time when checking repo-wide signing state, rather than letting a skill
framework's plan-and-report output substitute for actually running the
verification.

## Audit-verified known issues (confirmed present)

- **Unsigned package database (Critical) — FIXED.** Was: `shani.db`/
  `shani.files` (and their `.tar.gz` originals — `x86_64/shani.db` and
  `x86_64/shani.db.tar.gz` are byte-identical, same for `.files`; both
  pairs were signed independently rather than assuming one is a symlink
  of the other) had no `.sig` files, open across multiple ecosystem-wide
  audit passes (see `../REPO-AUDIT-2026-08-28.md`) despite every
  individual package already being signed. Signed all 4 files with the
  real project signing key (`7B927BFF...4792`, confirmed present on this
  host and matching `shani-keyring`'s documented fingerprint exactly —
  the user explicitly confirmed using it before this ran). **Verified for
  real, at the strongest level available**: `gpg --verify` confirms a
  good signature from the real key on all 4 files, and — the real test —
  a genuine `pacman -Sy` / `pacman -Si` run inside the `shani-builder`
  container, with `pacman-key --add`+`--lsign-key` on the real exported
  public key and `SigLevel = Required DatabaseOptional` (i.e. pacman
  configured to *reject* an unsigned or bad-signature database, not just
  tolerate one), successfully synced this repo and queried real package
  metadata from it. This is exactly the tampering-detection property the
  finding was about, confirmed against the actual client, not just a
  standalone `gpg --verify`. Left uncommitted in the working tree only —
  nothing pushed; publishing this needs to go through the real publish
  step in `shani-builder/pkg/pkg-builder.sh` per this file's own
  "Cross-repo impact" note below, not a one-off commit here.
  **Also fixed the actual root cause** so this doesn't silently regress
  on the next real publish: `pkg-builder.sh`'s `rebuild_database()` ran
  bare `repo-add shani.db.tar.gz *.pkg.tar.zst` with no `-s`/signing step
  at all — see that repo's `AGENTS.md` for the fix and how it was
  verified (a full real run of the corrected function against real
  package files, using a disposable test key with a known passphrase
  standing in for the real `GPG_PRIVATE_KEY`/`GPG_PASSPHRASE` CI secrets,
  which this session correctly never had or needed access to).
- **x86_64 only.** No other architecture directories exist.
- **CI status.** No CI workflows, no pre-commit hooks.
- **Real incident: a `git merge` of this repo produced a mismatched
  database signature, which cascaded into 56 packages being deleted from
  the live repo — FIXED.** After the unsigned-database fix above was
  committed and pushed (superseding the "left uncommitted" note), a
  concurrent automated CI push landed on `origin/main` first; resolving
  that with `git merge origin/main --no-edit` took the remote's newer,
  freshly-rebuilt `shani.db.tar.gz`/`shani.files.tar.gz` but kept the
  locally-generated `.sig` files for the *pre-merge* content (git merges
  independently-changed files by whichever side touched them — it has no
  idea a `.sig` is derived from its neighboring `.db`). The result: every
  real `pacman -Sy` against this repo hard-failed signature verification
  (`SigLevel = Required DatabaseOptional` treats a present-but-invalid
  signature as fatal, unlike a missing one), and the CI pipeline's own
  "remove stale packages" cleanup step then deleted 56 packages it
  believed were no longer needed — all of which then failed to rebuild
  because the underlying signature problem was still there. Fixed by
  `git revert`-ing the 56-file deletion commit and `git rm`-ing the 4
  mismatched `.sig` files outright (rather than trying to regenerate them
  without the real signing key), then letting the next real CI publish —
  running the fixed `pkg-builder.sh` (see `shani-builder/AUDIT-HISTORY.md`
  for the per-call GPG-key-file races that were also found and fixed
  during this same incident) — regenerate a correctly-signed database from
  scratch and merge that in cleanly. Verified via `tar tzf`
  database-vs-files consistency checks and confirming `shani.db.sig`/
  `shani.files.sig` were real, non-empty, and produced by the same publish
  run as the database content they accompany. See the new rule above for
  how to avoid recreating this.

## Cross-repo impact — check before calling a fix complete

This repo's output is published by `shani-builder/pkg/pkg-builder.sh`
(NOT `shani-pkgbuilds` — that repo only holds the PKGBUILD sources
packages get built from; confirmed via `grep -rln "repo-add"` across the
whole ecosystem) and consumed by every real Shanios install's
`pacman.conf`. If you change anything about how the database is signed
or structured, confirm `pkg-builder.sh`'s `rebuild_database()` still
produces something this repo (and real pacman clients) accept — don't
assume compatibility, check it.

## Where things are documented

`README.md` explains the `pacman.conf` entry clients use to add this repo
and the CNAME/Pages setup.
