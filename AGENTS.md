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

## Empirical verification (mandatory)

**Reading code is analysis; running code is verification.** A change is not
verified by reading the diff, running `bash -n`, or confirming it "looks
correct." It is verified by observing the actual behavior of the real
thing in the real environment — built, served, deployed, signed, running.
If you haven't seen it work (or fail) for real, it isn't verified.

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

## Boundaries

- ✅ **Always**: `gpg --verify` any `.sig` against its neighboring `.db`/
  `.files` bytes — post-merge, not just pre-merge — before pushing.
- ⚠️ **Ask first**: manually merging a locally-regenerated `.sig`/`.db` pair
  against `origin` — prefer letting the next real CI publish regenerate
  both together (see the rule above; this exact shortcut caused the
  56-package-deletion incident documented below).
- 🚫 **Never**: commit anything not meant to be fully public — everything
  here is served unauthenticated to the internet; double-check any added
  file isn't a private key, credential, or leaked build artifact.

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
- **CI status — corrected, was stale.** `.github/workflows/ci.yml` runs
  `scripts/check-repo-integrity.sh` on push/PR: verifies every `.sig`
  under `x86_64/` against the real signing key (imported into a throwaway
  `GNUPGHOME`, never the real keyring) and confirms every `.db`/`.files`
  archive is `tar -tzf`-parseable — 52/52 signatures, 4/4 archives
  verified live (2026-09-18). No pre-commit hooks.
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

## Garuda Cross-Reference Findings (added 2026-09-17)

Based on a full scan of 29 garuda-linux repos (see `../garuda-catalog.md`) mapped against shani (see `../shani-catalog.md`). chaotic-manager (repo publishing) is the most directly comparable repo — both publish packages to a local repository.

### 🟡 HIGH: CI/CD gap (shared across ALL repos)

1. **Shared CI templates** (estimated 2-3 days, affects ALL repos).
   - Garuda's `gitlab-ci-commons` provides reusable templates (commitizen, flake-check, pre-commit, tag-to-release). Each repo `include:`s from it.
   - Shani repos run on GitHub Actions (no `.gitlab-ci.yml` anywhere) — 8 repos (blog, builder, docs, fleet, insights, install-media, pkgbuilds, platform) carry hand-written `.github/workflows/*.yml` with duplicated patterns.
   - **Action**: Create `shani-ci-commons` (GitHub Actions reusable workflows / composite actions) with templates for lint, test, build, security scan. Each repo references them via `uses: shani8dev/shani-ci-commons/...` instead of copy-pasting.
   - **Affects**: All 15 shani repos.

### 🟡 HIGH: Dependency management gap

2. **Add automated dependency updates** (estimated 4 hours, affects ALL repos).
   - Garuda uses `renovate-runner` running hourly against all repos with `renovate.json` files.
   - Shani repos have no automated dependency updating.
   - **Action**: Set up Renovate (self-hosted or gitlab.com) with a fleet-wide config. Each repo adds a minimal `renovate.json`.

### 🟢 MEDIUM: Code quality

3. **Conventional commit enforcement** (estimated 2 hours, affects ALL repos).
   - Every garuda repo has a `[commitizen]` badge; `cz commit` is enforced.
   - Shani repos have no commit message standardization.

### 🔗 Cross-repo context

4. **This repo is generated output** — `shani-builder/pkg/pkg-builder.sh` builds, signs, and publishes packages here. This repo is mostly generated output from `shani-builder`, not hand-edited. Changes should originate in `shani-builder`, not here directly.

### 🔍 Re-Scan Findings (2026-09-17)

Re-scanned against `../garuda-catalog.md` (29 actual garuda repos — garuda-repo and others from the original 34-repo mapping do NOT exist).

**Confirmed mapping**: **chaotic-manager** (`garuda-clones/chaotic-manager/`) remains the closest counterpart — both publish packages to a repository — and the reference above is valid. **chaotic-portable-builder** also builds into a local repo.

**New gaps discovered** (chaotic-manager repo-management features shani-repo lacks):
1. **No repo-management API** — chaotic-manager's `repo-manager.ts` manages the repository programmatically (Express API on port 8080); shani-repo is static generated output with no management interface.
2. **No automated PKGBUILD update pipeline** — chaotic-manager's CI parses PKGBUILDs, builds schedules, and auto-updates from AUR/GitLab on half-hourly tag checks; shani-repo only receives what `pkg-builder.sh` pushes.
3. **No build/event notifications** — chaotic-manager ships `telegram-bot.ts`; shani-repo has no notification channel for publish events.
4. **No multi-arch support** — garuda repos serve multiple architectures; shani-repo is x86_64-only (already noted above).

**Shani advantages**:
1. **Signed database verified against real pacman** — `shani.db.sig`/`shani.files.sig` verified via a genuine `pacman -Sy` with `SigLevel = Required DatabaseOptional`; garuda relies on Chaotic-AUR keys.
2. **Documented merge-signature incident** — the `.sig`/`.db` merge-mismatch failure mode and its fix are documented in this file; garuda repos have no such documentation.
3. **Single signing key** (`7B927BFF...4792`) — simpler trust model than garuda's multi-key Chaotic-AUR setup.

### 📋 Implementation Roadmap (2026-09-17)

Implementation priorities are per `../IMPLEMENTATION-ROADMAP.md` (master roadmap for the whole shani ecosystem).

1. ~~**CI Workflow Verifying Repo Integrity** (P1, ~2-3 days).~~ **DONE (2026-09-18)** — see "Audit-verified known issues" above: `ci.yml` + `check-repo-integrity.sh` verify every `.sig`/`.db`/`.files` on push/PR. Not yet migrated to `shani-ci-commons` templates (still a standalone workflow, per the top-level AGENTS.md's note that this repo is not currently a `shani-ci-commons` consumer) — that migration is the remaining piece of this item, not the integrity check itself. Source: IMPLEMENTATION-ROADMAP.md #7.

2. **Automated Sync Check for `.db`/`.sig` Pairs** (P2, ~1 day) — Script to verify every `.db`/`.files`/`.sig` triplet verifies with GPG before and after any git merge or manual operation. This is the mechanical enforcement of the rule documented above ("a `git merge` here can silently break the database's signature"). Could be a pre-commit hook or a post-merge CI step — either way, the gap is that today this verification is only done by hand. Source: IMPLEMENTATION-ROADMAP.md (shani-repo gap analysis).

3. **Automated PKGBUILD Update Checks from AUR/GitLab** (P3, ~2-3 days) — Adapt chaotic-manager's `repo-manager.ts` pattern: scheduled CI pipeline that checks tracked packages for new upstream tags, opens a merge request when an update is available (not auto-merged — human review required). Currently shani-repo only receives what `pkg-builder.sh` pushes with no source-drift detection. Source: IMPLEMENTATION-ROADMAP.md #32.

4. **Renovate, Conventional Commits** (P1, ~2 hours, cross-repo) — Add fleet-wide Renovate for automated dependency updates and commitizen for conventional commit enforcement. This repo is mostly generated output, so Renovate's value is limited here — but conventional commits on the automated publish commits would make the git log meaningful for debugging which publish introduced a regression. Source: IMPLEMENTATION-ROADMAP.md #8, #9.

5. **Multi-Architecture Support** (P3, future consideration) — Currently x86_64 only with no other architecture directories. If shani targets ARM/aarch64 in the future, this repo would need a parallel architecture tree. Not urgent — x86_64-only is appropriate for shani's current hardware targets.
