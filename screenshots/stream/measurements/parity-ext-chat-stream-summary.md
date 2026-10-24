# dsh-flutter parity: parity-ext

Suite parity-ext: 224 cases in the manifest. light complete; dark sampled to 1-2 cases per surface (PARITY_EXT_ALL_THEMES=1 for all)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

24 captures: 24 compared, 0 same, 0 pass (official, > 96% pixel-perfect), 0 geometry pass (incl. those), 24 fail, 0 not covered, 0 missing. Mean pixel-perfect 83.36%, mean non-text 91.79%.

## Per case

| case | theme | pixel-perfect % | RGB % | close % | non-text % | status | main bucket |
|---|---|---:|---:|---:|---:|---|---|
| `components.chat-stream.to-bottom-desktop.light` | light | 80.62 | 99.76 | 94.98 | 81.49 | FAIL | hairline 89 px |
| `components.chat-stream.to-bottom-desktop.dark` | dark | 73.27 | 99.74 | 96.11 | 73.70 | FAIL | other 122 px |
| `components.chat-stream.to-bottom-phone.light` | light | 82.94 | 99.08 | 94.59 | 83.75 | FAIL | offset 662 px |
| `components.chat-stream.to-bottom-phone.dark` | dark | 74.79 | 99.18 | 93.31 | 75.80 | FAIL | offset 712 px |
| `components.chat-stream.hint-desktop.light` | light | 75.24 | 99.29 | 87.35 | 96.24 | FAIL | text 397 px |
| `components.chat-stream.hint-desktop.dark` | dark | 73.97 | 98.61 | 78.62 | 96.67 | FAIL | text 429 px |
| `components.chat-stream.hint-phone.light` | light | 84.49 | 95.98 | 86.38 | 94.62 | FAIL | text 1399 px |
| `components.chat-stream.hint-phone.dark` | dark | 79.93 | 94.66 | 80.83 | 90.63 | FAIL | text 1477 px |
| `components.chat-stream.load-earlier-desktop.light` | light | 81.87 | 97.26 | 84.26 | 94.61 | FAIL | text 293 px |
| `components.chat-stream.load-earlier-desktop.dark` | dark | 81.48 | 96.87 | 83.35 | 94.09 | FAIL | text 290 px |
| `components.chat-stream.load-earlier-phone.light` | light | 85.83 | 98.34 | 86.77 | 90.98 | FAIL | hairline 1277 px |
| `components.chat-stream.load-earlier-phone.dark` | dark | 85.22 | 97.81 | 85.97 | 90.52 | FAIL | hairline 1341 px |
| `components.chat-stream.load-earlier-loading-desktop.light` | light | 81.45 | 98.45 | 84.65 | 95.60 | FAIL | text 283 px |
| `components.chat-stream.load-earlier-loading-desktop.dark` | dark | 81.45 | 98.13 | 83.90 | 95.50 | FAIL | text 281 px |
| `components.chat-stream.load-earlier-loading-phone.light` | light | 85.83 | 99.15 | 87.66 | 91.30 | FAIL | hairline 1068 px |
| `components.chat-stream.load-earlier-loading-phone.dark` | dark | 85.35 | 98.86 | 86.43 | 90.99 | FAIL | hairline 1089 px |
| `components.chat-stream.actions-user-desktop.light` | light | 84.94 | 99.10 | 89.00 | 96.04 | FAIL | text 429 px |
| `components.chat-stream.actions-user-desktop.dark` | dark | 84.70 | 98.70 | 86.85 | 95.99 | FAIL | text 436 px |
| `components.chat-stream.actions-user-phone.light` | light | 92.64 | 99.05 | 93.68 | 95.80 | FAIL | hairline 914 px |
| `components.chat-stream.actions-user-phone.dark` | dark | 92.44 | 98.75 | 93.17 | 95.89 | FAIL | hairline 949 px |
| `components.chat-stream.actions-tail-desktop.light` | light | 84.11 | 98.62 | 87.85 | 95.30 | FAIL | text 398 px |
| `components.chat-stream.actions-tail-desktop.dark` | dark | 83.92 | 98.04 | 85.66 | 95.25 | FAIL | text 403 px |
| `components.chat-stream.actions-tail-phone.light` | light | 92.24 | 99.00 | 93.73 | 96.10 | FAIL | text 951 px |
| `components.chat-stream.actions-tail-phone.dark` | dark | 92.07 | 98.67 | 92.93 | 96.07 | FAIL | text 986 px |

## Per area

| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |
|---|---:|---:|---:|---:|---:|
| chat-stream | 24 | 24 | 0 | 83.37 | 91.79 |
