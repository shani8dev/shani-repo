#!/usr/bin/env bash
#
# check-repo-integrity.sh — Verify pacman repository integrity for shani-repo.
#
# For every .sig file under x86_64/:
#   1. Verifies the signature against the real project signing key
#      (imported from ../shani-keyring/shani.gpg into a throwaway GNUPGHOME).
#   2. For database archives (.db, .db.tar.gz, .files, .files.tar.gz),
#      confirms the archive is parseable with `tar -tzf` and lists package
#      entries.
#
# Exits non-zero on any failure, naming the broken file in the message.
#
# This guards against the documented incident where a `git merge` silently
# produced a mismatched .sig/.db pair, causing pacman clients to hard-fail
# signature verification and triggering a cascade that deleted 56 packages.
#
# Usage:
#   scripts/check-repo-integrity.sh [REPO_DIR]
#
# Environment:
#   REPO_DIR  — path to the repo root (default: script's parent's parent)
#   KEYRING   — path to the public key file (default: ../shani-keyring/shani.gpg)
#   EXPECTED_FINGERPRINT — expected key fingerprint (default: 7B927BFF...4792)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_DIR="${1:-${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"
ARCH_DIR="${REPO_DIR}/x86_64"
# Auto-detect the keyring layout: locally it's a sibling
# (../shani-keyring/shani.gpg); in CI it's a child checkout
# (shani-keyring/shani.gpg) — actions/checkout@v4 rejects any `path`
# outside the caller repo, so the CI layout is the child one.
# Verified live: both layouts point at the same shani.gpg.
if [[ -f "${REPO_DIR}/shani-keyring/shani.gpg" ]]; then
    KEYRING="${KEYRING:-${REPO_DIR}/shani-keyring/shani.gpg}"
else
    KEYRING="${KEYRING:-${REPO_DIR}/../shani-keyring/shani.gpg}"
fi
EXPECTED_FINGERPRINT="${EXPECTED_FINGERPRINT:-7B927BFF D4A9 EAAA 8B66 6B77 DE21 7F3D A801 4792}"

# Files that are pacman database/files archives (not packages)
DB_ARCHIVE_PATTERN='shani\.(db|files)(\.tar\.gz)?$'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '[check-repo-integrity] %s\n' "$*" >&2; }
fail() { printf '[check-repo-integrity] ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

[[ -d "${ARCH_DIR}" ]] || fail "Architecture directory not found: ${ARCH_DIR}"
[[ -f "${KEYRING}" ]]  || fail "Public key not found: ${KEYRING}"

command -v gpg >/dev/null 2>&1 || fail "gpg is required but not found in PATH"
command -v tar >/dev/null 2>&1 || fail "tar is required but not found in PATH"

# ---------------------------------------------------------------------------
# Set up throwaway GNUPGHOME
# ---------------------------------------------------------------------------

TMP_GPGHOME="$(mktemp -d)"
trap 'rm -rf "${TMP_GPGHOME}"' EXIT

log "Importing public key from ${KEYRING} into temporary GNUPGHOME (${TMP_GPGHOME})"

# Import the key — fail if import fails (broken trust chain is a hard failure)
if ! gpg --homedir "${TMP_GPGHOME}" --import "${KEYRING}" >/dev/null 2>&1; then
    fail "Failed to import public key from ${KEYRING} — trust chain is broken"
fi

# Verify the imported key fingerprint matches the expected project key
IMPORTED_FP="$(gpg --homedir "${TMP_GPGHOME}" --list-keys --with-fingerprint --with-colons 2>/dev/null \
    | awk -F: '/^fpr/ {print $10}' | head -1)"

# Normalize: remove spaces for comparison
NORMALIZED_FP="$(echo "${IMPORTED_FP}" | tr -d ' ')"
NORMALIZED_EXPECTED="$(echo "${EXPECTED_FINGERPRINT}" | tr -d ' ')"

if [[ "${NORMALIZED_FP}" != "${NORMALIZED_EXPECTED}" ]]; then
    fail "Imported key fingerprint (${IMPORTED_FP}) does not match expected project key (${EXPECTED_FINGERPRINT})"
fi

log "Key verified: ${IMPORTED_FP} (matches expected project signing key)"

# ---------------------------------------------------------------------------
# Collect all .sig files
# ---------------------------------------------------------------------------

SIG_FILES=()
while IFS= read -r -d '' sig; do
    SIG_FILES+=("${sig}")
done < <(find "${ARCH_DIR}" -maxdepth 1 -name '*.sig' -print0 | sort -z)

if [[ ${#SIG_FILES[@]} -eq 0 ]]; then
    fail "No .sig files found under ${ARCH_DIR}"
fi

log "Found ${#SIG_FILES[@]} signature file(s) to verify"

# ---------------------------------------------------------------------------
# Verify each signature
# ---------------------------------------------------------------------------

FAILURES=0
PASSED=0

for sig_file in "${SIG_FILES[@]}"; do
    # The signed file is the .sig path with the .sig suffix removed
    signed_file="${sig_file%.sig}"

    # Check the signed file exists
    if [[ ! -f "${signed_file}" ]]; then
        log "FAIL: ${sig_file} — signed file ${signed_file} does not exist"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # Verify the signature
    if ! gpg --homedir "${TMP_GPGHOME}" --verify "${sig_file}" "${signed_file}" >/dev/null 2>&1; then
        log "FAIL: ${sig_file} — signature does not verify against project key"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # For database archives, also verify the archive is parseable
    if [[ "$(basename "${signed_file}")" =~ ${DB_ARCHIVE_PATTERN} ]]; then
        if ! tar -tzf "${signed_file}" >/dev/null 2>&1; then
            log "FAIL: ${signed_file} — archive is not parseable (tar -tzf failed)"
            FAILURES=$((FAILURES + 1))
            continue
        fi

        # Confirm the archive lists at least one package entry
        ENTRY_COUNT="$(tar -tzf "${signed_file}" 2>/dev/null | wc -l)"
        if [[ "${ENTRY_COUNT}" -eq 0 ]]; then
            log "FAIL: ${signed_file} — archive is empty (no package entries)"
            FAILURES=$((FAILURES + 1))
            continue
        fi

        log "OK: ${sig_file} — signature valid, archive parseable (${ENTRY_COUNT} entries)"
    else
        log "OK: ${sig_file} — signature valid"
    fi

    PASSED=$((PASSED + 1))
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log "----------------------------------------"
log "Verification complete: ${PASSED} passed, ${FAILURES} failed"

if [[ ${FAILURES} -gt 0 ]]; then
    fail "${FAILURES} signature(s) failed verification — repo integrity check FAILED"
fi

log "All signatures verify and all database archives are parseable."
exit 0
