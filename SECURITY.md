# Security Policy

## Trust Model

`shani-repo` is the published pacman package repository for Shanios
(`repo.shani.dev/$arch`). It serves signed packages and the package database
that pacman clients use to discover and install Shanios packages.

The trust chain is:

1. Packages are GPG-signed before upload (by `shani-builder`).
2. Clients verify package signatures against `shani-keyring` (`shani.gpg`).
3. The package database (`shani.db`/`shani.files`) tells pacman which packages
   are available and their checksums.

## Key Security Mechanisms

| Mechanism | Implementation |
|-----------|----------------|
| Package signing | Every `.pkg.tar.zst` has a detached `.sig` file (GPG-signed by `shani-builder`) |
| Trust root | `shani-keyring` (`shani.gpg`) is the pacman trust root |
| Database | `shani.db` + `shani.files` serve package metadata to clients |

## Known Limitations

- **Unsigned package database.** `shani.db` and `shani.files` currently have no `.sig` files, while every individual package is signed. A tampered database (adding a malicious package version, removing a security update) is undetectable by clients. Sign the database and ship `.sig` files.

## Reporting a Vulnerability

If you discover a security vulnerability in any Shanios project, please report it
responsibly by opening a private security advisory on GitHub.

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 72 hours and provide a detailed response
within 7 days. Thank you for helping keep Shanios secure.
