# dsh-flutter parity: parity-ext

Suite parity-ext: 342 cases in the manifest. all themes, every case (PARITY_EXT_ALL_THEMES=1)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

40 captures: 40 compared, 0 same, 8 pass (official, > 96% pixel-perfect), 8 geometry pass (incl. those), 32 fail, 0 not covered, 0 missing. Mean pixel-perfect 95.38%, mean non-text 98.72%.

## Per case

| case | theme | pixel-perfect % | RGB % | close % | non-text % | status | main bucket |
|---|---|---:|---:|---:|---:|---|---|
| `components.system-prompt.closed-desktop-en.light` | light | 95.81 | 99.89 | 98.00 | 99.36 | FAIL | text 409 px |
| `components.system-prompt.closed-desktop-en.dark` | dark | 95.14 | 99.77 | 96.59 | 98.91 | FAIL | text 434 px |
| `components.system-prompt.closed-desktop-zh.light` | light | 95.41 | 99.91 | 97.76 | 99.38 | FAIL | text 458 px |
| `components.system-prompt.closed-desktop-zh.dark` | dark | 94.70 | 99.79 | 96.59 | 98.89 | FAIL | text 483 px |
| `components.system-prompt.closed-phone-en.light` | light | 95.61 | 99.60 | 96.44 | 97.93 | FAIL | text 920 px |
| `components.system-prompt.closed-phone-en.dark` | dark | 95.38 | 99.45 | 95.97 | 97.75 | FAIL | text 943 px |
| `components.system-prompt.closed-phone-zh.light` | light | 95.44 | 99.77 | 96.99 | 97.44 | FAIL | hairline 818 px |
| `components.system-prompt.closed-phone-zh.dark` | dark | 95.30 | 99.66 | 96.06 | 97.39 | FAIL | text 829 px |
| `components.system-prompt.open-desktop-en.light` | light | 94.63 | 99.71 | 96.95 | 99.33 | FAIL | text 2297 px |
| `components.system-prompt.open-desktop-en.dark` | dark | 94.55 | 99.40 | 95.10 | 99.27 | FAIL | text 2311 px |
| `components.system-prompt.open-desktop-zh.light` | light | 94.57 | 99.72 | 96.92 | 99.33 | FAIL | text 2331 px |
| `components.system-prompt.open-desktop-zh.dark` | dark | 94.45 | 99.40 | 95.03 | 99.27 | FAIL | text 2359 px |
| `components.system-prompt.open-phone-en.light` | light | 95.21 | 99.44 | 96.42 | 98.03 | FAIL | text 5509 px |
| `components.system-prompt.open-phone-en.dark` | dark | 95.15 | 99.19 | 95.75 | 98.00 | FAIL | text 5550 px |
| `components.system-prompt.open-phone-zh.light` | light | 95.17 | 99.47 | 96.42 | 97.94 | FAIL | text 5399 px |
| `components.system-prompt.open-phone-zh.dark` | dark | 95.13 | 99.24 | 95.74 | 97.91 | FAIL | text 5435 px |
| `components.system-prompt.update-open-desktop-en.light` | light | 94.16 | 99.70 | 96.69 | 99.27 | FAIL | text 2499 px |
| `components.system-prompt.update-open-desktop-en.dark` | dark | 94.08 | 99.36 | 94.68 | 99.20 | FAIL | text 2512 px |
| `components.system-prompt.update-open-desktop-zh.light` | light | 94.10 | 99.71 | 96.66 | 99.28 | FAIL | text 2535 px |
| `components.system-prompt.update-open-desktop-zh.dark` | dark | 93.96 | 99.36 | 94.59 | 99.20 | FAIL | text 2567 px |
| `components.system-prompt.update-open-phone-en.light` | light | 94.81 | 99.39 | 96.10 | 97.85 | FAIL | text 5934 px |
| `components.system-prompt.update-open-phone-en.dark` | dark | 94.75 | 99.13 | 95.38 | 97.82 | FAIL | text 5981 px |
| `components.system-prompt.update-open-phone-zh.light` | light | 94.82 | 99.46 | 96.18 | 97.73 | FAIL | text 5691 px |
| `components.system-prompt.update-open-phone-zh.dark` | dark | 94.77 | 99.20 | 95.42 | 97.71 | FAIL | text 5732 px |
| `components.system-prompt.long-open-desktop-en.light` | light | 92.80 | 99.74 | 95.99 | 99.37 | FAIL | text 5451 px |
| `components.system-prompt.long-open-desktop-en.dark` | dark | 92.75 | 99.34 | 93.42 | 99.32 | FAIL | text 5455 px |
| `components.system-prompt.long-open-desktop-zh.light` | light | 92.76 | 99.75 | 95.97 | 99.37 | FAIL | text 5485 px |
| `components.system-prompt.long-open-desktop-zh.dark` | dark | 92.69 | 99.34 | 93.38 | 99.32 | FAIL | text 5503 px |
| `components.system-prompt.long-open-phone-en.light` | light | 96.05 | 98.30 | 96.97 | 98.37 | FAIL | text 6643 px |
| `components.system-prompt.long-open-phone-en.dark` | dark | 95.82 | 97.85 | 96.32 | 98.13 | FAIL | text 6633 px |
| `components.system-prompt.long-open-phone-zh.light` | light | 96.03 | 98.32 | 96.98 | 98.31 | FAIL | text 6533 px |
| `components.system-prompt.long-open-phone-zh.dark` | dark | 95.80 | 97.88 | 96.32 | 98.08 | FAIL | text 6518 px |
| `components.system-prompt.empty-open-desktop-en.light` | light | 97.98 | 99.94 | 99.08 | 99.63 | basic pass | text 428 px |
| `components.system-prompt.empty-open-desktop-en.dark` | dark | 97.89 | 99.83 | 98.31 | 99.53 | basic pass | text 425 px |
| `components.system-prompt.empty-open-desktop-zh.light` | light | 97.85 | 99.95 | 99.03 | 99.63 | basic pass | text 462 px |
| `components.system-prompt.empty-open-desktop-zh.dark` | dark | 97.70 | 99.83 | 98.16 | 99.53 | basic pass | text 473 px |
| `components.system-prompt.empty-open-phone-en.light` | light | 98.06 | 99.81 | 98.53 | 99.18 | basic pass | text 1004 px |
| `components.system-prompt.empty-open-phone-en.dark` | dark | 97.98 | 99.72 | 98.37 | 99.11 | basic pass | text 1009 px |
| `components.system-prompt.empty-open-phone-zh.light` | light | 97.99 | 99.90 | 98.55 | 98.99 | basic pass | text 894 px |
| `components.system-prompt.empty-open-phone-zh.dark` | dark | 97.93 | 99.82 | 98.36 | 98.93 | basic pass | text 894 px |

## Per area

| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |
|---|---:|---:|---:|---:|---:|
| system-prompt | 40 | 40 | 8 | 95.38 | 98.72 |
