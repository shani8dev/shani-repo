# shani-repo
Repository for Shanios packages, served via GitHub Pages at the custom
domain `repo.shani.dev` (see `CNAME`).

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

This repo currently serves `x86_64` packages only.
