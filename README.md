# shani-repo
Repository for Shani OS packages, served via GitHub Pages at the custom
domain `repo.shani.dev` (see `CNAME`).

Add the following to your `pacman.conf` — this is exactly what ShaniOS's
own images ship in `/etc/pacman.conf`:
```
[shani]
Server = https://repo.shani.dev/$arch
```

`SigLevel` doesn't need to be set per-repo here — it inherits the global
`[options]` default (`Required DatabaseOptional`), which requires valid
package signatures. On a non-ShaniOS Arch system, trust the signing key
first (packages in this repo are signed with it, so pacman needs it before
it will install anything from `[shani]` — including `shani-keyring` itself):
```
sudo pacman-key --recv-key 7B927BFFD4A9EAAA8B666B77DE217F3DA8014792 --keyserver keys.openpgp.org
sudo pacman-key --lsign-key 7B927BFFD4A9EAAA8B666B77DE217F3DA8014792
```
(ShaniOS itself ships with this repo and key already configured — nothing
to do there.)
