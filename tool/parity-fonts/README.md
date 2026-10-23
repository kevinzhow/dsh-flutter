# Parity fonts

Deterministic text for both parity providers (see `docs/parity.md`, "Fonts").

dsh's web client ships one font, Montserrat (brand wordmark). Its text stack is system fonts, so on a
capture machine the face would depend on fontconfig. The providers instead pin Noto Sans under the
leading names of that stack (`-apple-system`, `BlinkMacSystemFont`, `Segoe UI`):

- React provider: `tool/parity-web/capture.mjs` serves `files/*` through an `@font-face` for the three names.
- Flutter provider: `dsh_parity` registers the same files with one `FontLoader` per name.
- `tool/parity fonts` verifies the sha256 of every file against `manifest.json`; both providers
  record the face files and digests in each capture's metadata.

The code stack (`'SF Mono', 'JetBrains Mono', ...`) is pinned the same way: Noto Sans Mono (Debian `fonts-noto-mono`) is
served and registered under `SF Mono`.

Noto Sans is SIL OFL 1.1 (`OFL.txt`), taken from Debian `fonts-noto-core` 20201225. Only Regular and Bold
exist, so CSS weights 500/600 select Regular/Bold the same way on both sides. Not vendored yet: Montserrat
and CJK faces (see `notVendored` in `manifest.json`).
