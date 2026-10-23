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
exist, so CSS weights 500/600 select Regular/Bold the same way on both sides.

Chinese text: `files/NotoSansCJKsc-{Regular,Bold}.subset.otf` (SIL OFL 1.1, `OFL-NotoSansCJK.txt`) are subsets of Noto Sans CJK SC
2.004 from Ubuntu/Debian `fonts-noto-cjk` 1:20240730+repack1-1build1, registered under `PingFang SC` (the first CJK name of
the text and the code stack) on both providers. The glyph set is `cjk-charset.txt` (3000 most frequent GB 2312 hanzi, CJK
and fullwidth punctuation, the characters of dsh's conversation dictionary); `subset-cjk.py` rebuilds the files
byte for byte from the installed package (needs fontTools). The extension builders assert that the text of a zh-CN case is
inside the charset (`parity_lib/fonts.py: uncovered_cjk`). Not vendored yet: Montserrat (see `notVendored` in
`manifest.json`).
