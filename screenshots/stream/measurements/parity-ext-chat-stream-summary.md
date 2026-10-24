# dsh-flutter parity: parity-ext

Suite parity-ext: 276 cases in the manifest. light complete; dark sampled to 1-2 cases per surface (PARITY_EXT_ALL_THEMES=1 for all)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

24 captures: 24 compared, 0 same, 0 pass (official, > 96% pixel-perfect), 0 geometry pass (incl. those), 24 fail, 0 not covered, 0 missing. Mean pixel-perfect 83.40%, mean non-text 91.87%.

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
| `components.chat-stream.actions-user-desktop.light` | light | 84.83 | 99.15 | 89.18 | 96.35 | FAIL | text 445 px |
| `components.chat-stream.actions-user-desktop.dark` | dark | 84.58 | 98.76 | 86.98 | 96.30 | FAIL | text 453 px |
| `components.chat-stream.actions-user-phone.light` | light | 92.90 | 99.12 | 93.96 | 96.06 | FAIL | hairline 899 px |
| `components.chat-stream.actions-user-phone.dark` | dark | 92.58 | 98.84 | 93.45 | 96.04 | FAIL | hairline 965 px |
| `components.chat-stream.actions-tail-desktop.light` | light | 84.17 | 98.67 | 87.99 | 95.44 | FAIL | text 401 px |
| `components.chat-stream.actions-tail-desktop.dark` | dark | 84.00 | 98.09 | 85.77 | 95.42 | FAIL | text 406 px |
| `components.chat-stream.actions-tail-phone.light` | light | 92.59 | 99.11 | 94.10 | 96.42 | FAIL | text 945 px |
| `components.chat-stream.actions-tail-phone.dark` | dark | 92.34 | 98.81 | 93.28 | 96.33 | FAIL | text 982 px |

## Per area

| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |
|---|---:|---:|---:|---:|---:|
| chat-stream | 24 | 24 | 0 | 83.40 | 91.87 |
