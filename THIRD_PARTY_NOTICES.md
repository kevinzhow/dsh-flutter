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

## Noto Sans and Noto Sans Mono (visual parity tool)

`tool/parity-fonts/files/NotoSans-Regular.ttf`, `NotoSans-Bold.ttf`, `NotoSansMono-Regular.ttf` and `NotoSansMono-Bold.ttf`
are used only by the visual parity tool (`docs/parity.md`) so that the React and Flutter captures draw text with the same
faces. Noto Sans and Noto Sans Mono are copyright
2010, 2012-2020 Google Inc. and 2015-2020 Google LLC, licensed under the SIL Open Font License 1.1
(`tool/parity-fonts/OFL.txt`). They are not part of the app.

## path_drawing

`packages/dsh_ui` parses the SVG path data of dsh's product icons with the `path_drawing` package (BSD 3-Clause, Dart
project authors / Flutter community), a Dart dependency resolved through pub.
