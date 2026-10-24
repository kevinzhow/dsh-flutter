# Third-party notices

This repository contains data and types generated from, and a Dart port of client logic from, DeepSeek Harness (DSH):
theme tokens (`packages/dsh_theme`), UI copy (`packages/dsh_i18n`), Remote and session-event types
(`packages/dsh_client/lib/src/generated`, `packages/dsh_models/lib/src/generated`), and the behaviour of the session
event window (`packages/dsh_models`). Pinned version: see `docs/upstream-sync.json`.

DeepSeek Harness is licensed under the MIT License:

MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Raft visual-testing CLI (visual parity tool)

`tool/vendor/raft-visual-testing/` is a verbatim copy of `packages/visual-testing` from
[botiverse/raft-source](https://github.com/botiverse/raft-source), tag `v1.21.23-source.1`, commit
`db5e399f017d584e49597e3a28757645d6807893`, Copyright 2026 Botiverse, Inc. **That directory is not MIT.** It is licensed
under the Functional Source License, Version 1.1, ALv2 Future License (FSL-1.1-ALv2); the unmodified license text is
`tool/vendor/raft-visual-testing/LICENSE`, and `tool/vendor/raft-visual-testing/README-VENDOR.md` records its origin, the
Permitted Purpose this repository relies on (internal development and test tool, not offered to others) and how to
update it. The tool is used only by the visual parity tool (`docs/parity.md`) for manifest validation, diff metrics,
the side-by-side images and the HTML report; it is not part of the app. The FSL terms apply to every copy of it:
keep its `LICENSE` and copyright notice. Its runtime dependency `sharp` (Apache-2.0, with LGPL-3.0-or-later libvips
binaries) is installed on demand by `tool/parity setup` and is not committed.

## Noto Sans and Noto Sans Mono (visual parity tool)

`tool/parity-fonts/files/NotoSans-Regular.ttf`, `NotoSans-Bold.ttf`, `NotoSansMono-Regular.ttf` and `NotoSansMono-Bold.ttf`
are used only by the visual parity tool (`docs/parity.md`) so that the React and Flutter captures draw text with the same
faces. Noto Sans and Noto Sans Mono are copyright
2010, 2012-2020 Google Inc. and 2015-2020 Google LLC, licensed under the SIL Open Font License 1.1
(`tool/parity-fonts/OFL.txt`). They are not part of the app.

## Noto Sans CJK SC subset (visual parity tool)

`tool/parity-fonts/files/NotoSansCJKsc-Regular.subset.otf` and `NotoSansCJKsc-Bold.subset.otf` are used only by the visual
parity tool (`docs/parity.md`) so that the React and Flutter captures draw Chinese text with the same face. They are
subsets (about 3200 glyphs, no hinting or layout tables, made by `tool/parity-fonts/subset-cjk.py`) of the SC face of Noto
Sans CJK 2.004 from the Ubuntu/Debian package `fonts-noto-cjk` 1:20240730+repack1-1build1 (upstream
https://github.com/notofonts/noto-cjk). Copyright 2014-2021 Adobe (http://www.adobe.com/), licensed under the SIL Open Font
License 1.1 (`tool/parity-fonts/OFL-NotoSansCJK.txt`). They are not part of the app.

## path_drawing

`packages/dsh_ui` parses the SVG path data of dsh's product icons with the `path_drawing` package (BSD 3-Clause, Dart
project authors / Flutter community), a Dart dependency resolved through pub.

## Notification, settings and preference dependencies (apps/dsh_flutter)

`apps/dsh_flutter` resolves three packages through pub: `flutter_local_notifications` (BSD 3-Clause, MaiKaim), `app_settings`
(MIT, Spencer Collins) and `shared_preferences` (BSD 3-Clause, Flutter team). No source or asset of them is copied into
this repository.

## Syntax highlighter: TextMate engine and grammars (packages/dsh_highlight)

`packages/dsh_highlight` reproduces the syntax colouring of dsh web, which uses [shiki](https://github.com/shikijs/shiki)
with its css-variables theme. Three things in it come from other projects, all MIT-licensed:

- The tokenizer (`lib/src/tokenizer.dart`, `rules.dart`, `theme.dart`) is a Dart port of the algorithms of
  [vscode-textmate](https://github.com/microsoft/vscode-textmate) (Copyright (c) Microsoft Corporation, MIT): rule
  compilation, `$self`/`$base`/repository/scope includes, begin/end/while rules, captures, anchors, injections, the
  scope stack and the theme matching trie.
- The scope selectors, precedence and font styles of the theme (`lib/src/theme.dart`) are the `tokenColors` of shiki's
  `createCssVariablesTheme` ([shiki](https://github.com/shikijs/shiki), Copyright (c) 2021 Pine Wu, Copyright (c) 2023
  Anthony Fu, MIT), and the Oniguruma-to-RegExp translator (`lib/src/onig_translator.dart`) follows the behaviour
  of [oniguruma-to-es](https://github.com/slevithan/oniguruma-to-es) (Copyright (c) 2024-2026 Steven Levithan, MIT),
  which is what shiki's JavaScript regex engine uses; the mapping of POSIX classes and Unicode shorthands is taken from
  it. The translator and the tokenizer are separate Dart code, not copies of those sources.
- The grammars under `packages/dsh_highlight/assets/grammars/` are the TextMate grammars of `@shikijs/langs` (MIT), a
  collection of grammars written by many projects. `packages/dsh_highlight/assets/grammars/PROVENANCE.md` lists, for
  every grammar, its upstream repository, that repository's licence and copyright line, and the pinned source file.

The grammars are distributed under the licences of their upstream repositories, which are the following.

MIT License, Copyright (c) the holders named in `PROVENANCE.md` for the grammars it marks MIT (Jeff Hykin, .NET Foundation,
Microsoft, Furkan Ozalp, Prisma Data Services, Karuna Murti, GitHub Inc., George Fraser and fwcd, sumneko, MagicStack Inc.,
Shopify Inc., Dustin Pomerleau, Jacob Bandes-Storch, Pine Wu and Anthony Fu):

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
    documentation files (the "Software"), to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of
    the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
    THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
    CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
    IN THE SOFTWARE.

BSD 3-Clause License, for the `dart` grammar (dart-lang/dart-syntax-highlight): Copyright 2020, the Dart project authors.

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
    following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the
      following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
      following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of Google LLC nor the names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
    INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

TextMate bundle notice, for the `diff`, `html`, `ini`, `toml` and `yaml` grammars (textmate/diff.tmbundle,
textmate/html.tmbundle, textmate/ini.tmbundle, textmate/toml.tmbundle, textmate/yaml.tmbundle). These repositories
state no MIT/BSD licence; their README says:

    If not otherwise specified, files in this repository fall under the following license:

    Permission to copy, use, modify, sell and distribute this software is granted. This software is provided "as is"
    without express or implied warranty, and with no claim as to its suitability for any purpose.

This wording is permissive but is not one of the licences this repository otherwise accepts; those five grammars can be
removed with the `withheld` list in `tool/highlight/languages.json` (see `PROVENANCE.md`).

## QR scanning (mobile_scanner, ML Kit barcode scanning)

The pairing screen scans the QR code of a host's launch link with the camera through the
[`mobile_scanner`](https://pub.dev/packages/mobile_scanner) Flutter plugin (BSD-3-Clause, Copyright Julian Steenbakker
and contributors; it ships with its own `LICENSE`, which Flutter's licence page lists). On Android the plugin decodes with
Google's ML Kit barcode scanning library (`com.google.mlkit:barcode-scanning`, the bundled model, so no Google Play services
are required); on iOS and macOS it uses Apple's Vision framework. ML Kit is not open source: it is distributed as a binary
under [Google's ML Kit terms](https://developers.google.com/ml-kit/terms), which the app's Android build pulls in as a
Gradle dependency. The decoder runs on the device; nothing it sees leaves the phone. A build without the camera (desktop)
does not include it, and pasting the launch link is always available.

The certificate fingerprint uses `package:crypto` (BSD-3-Clause, the Dart team).

## xterm (terminal emulator, features/dsh_feature_sidebar_terminal)

`features/dsh_feature_sidebar_terminal` draws the sidebar terminal with the [`xterm`](https://pub.dev/packages/xterm) Dart
package, version 4.0.0 (MIT, Copyright (c) 2020 xuty, TerminalStudio), resolved through pub; no source is copied into this
repository. Its own dependencies are `equatable` (MIT, Felix Angelov), `quiver` (Apache-2.0, Google LLC) and `zmodem`
(MIT, xuty). The choice is recorded in `docs/terminal.md`.

The visual parity tool (`tool/parity-web`, development and test only, not part of the app) adds the npm packages `@xterm/xterm`
and `@xterm/addon-fit` (MIT, Copyright (c) 2017-2022 The xterm.js authors and 2014-2016 SourceLair, Microsoft Corporation and
contributors) because dsh web's terminal is built on them and the React provider mounts that real component.
