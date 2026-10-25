# dsh-flutter parity: parity-ext

Suite parity-ext: 374 cases in the manifest. all themes, every case (PARITY_EXT_ALL_THEMES=1)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

72 captures: 72 compared, 0 same, 12 pass (official, > 96% pixel-perfect), 12 geometry pass (incl. those), 60 fail, 0 not covered, 0 missing. Mean pixel-perfect 93.81%, mean non-text 98.20%.

## Per case

| case | theme | pixel-perfect % | RGB % | close % | non-text % | status | main bucket |
|---|---|---:|---:|---:|---:|---|---|
| `components.model-retry.scheduled-closed-desktop-en.light` | light | 91.49 | 99.69 | 95.30 | 98.70 | FAIL | text 830 px |
| `components.model-retry.scheduled-closed-desktop-en.dark` | dark | 91.18 | 99.46 | 92.79 | 98.77 | FAIL | text 874 px |
| `components.model-retry.scheduled-closed-desktop-zh.light` | light | 90.36 | 99.72 | 95.05 | 98.40 | FAIL | text 927 px |
| `components.model-retry.scheduled-closed-desktop-zh.dark` | dark | 89.98 | 99.46 | 92.04 | 98.55 | FAIL | text 987 px |
| `components.model-retry.scheduled-closed-phone-en.light` | light | 91.89 | 99.23 | 93.61 | 96.41 | FAIL | text 1793 px |
| `components.model-retry.scheduled-closed-phone-en.dark` | dark | 91.74 | 98.94 | 92.70 | 96.48 | FAIL | text 1881 px |
| `components.model-retry.scheduled-closed-phone-zh.light` | light | 91.37 | 99.50 | 93.67 | 95.58 | FAIL | text 1671 px |
| `components.model-retry.scheduled-closed-phone-zh.dark` | dark | 91.12 | 99.25 | 92.55 | 95.49 | FAIL | text 1733 px |
| `components.model-retry.started-closed-desktop-en.light` | light | 91.91 | 99.70 | 95.60 | 99.07 | FAIL | text 825 px |
| `components.model-retry.started-closed-desktop-en.dark` | dark | 91.58 | 99.49 | 93.10 | 99.05 | FAIL | text 860 px |
| `components.model-retry.started-closed-desktop-zh.light` | light | 91.10 | 99.72 | 95.22 | 98.57 | FAIL | text 860 px |
| `components.model-retry.started-closed-desktop-zh.dark` | dark | 90.75 | 99.48 | 92.67 | 98.76 | FAIL | text 922 px |
| `components.model-retry.started-closed-phone-en.light` | light | 92.00 | 99.24 | 93.38 | 96.29 | FAIL | text 1704 px |
| `components.model-retry.started-closed-phone-en.dark` | dark | 91.83 | 98.96 | 92.61 | 96.36 | FAIL | text 1798 px |
| `components.model-retry.started-closed-phone-zh.light` | light | 91.89 | 99.54 | 94.11 | 95.84 | FAIL | text 1571 px |
| `components.model-retry.started-closed-phone-zh.dark` | dark | 91.71 | 99.32 | 93.02 | 95.82 | FAIL | text 1634 px |
| `components.model-retry.started-open-desktop-en.light` | light | 92.80 | 99.73 | 96.05 | 99.00 | FAIL | text 1935 px |
| `components.model-retry.started-open-desktop-en.dark` | dark | 92.64 | 99.47 | 93.75 | 98.97 | FAIL | text 1977 px |
| `components.model-retry.started-open-desktop-zh.light` | light | 91.78 | 99.70 | 95.07 | 98.87 | FAIL | text 2211 px |
| `components.model-retry.started-open-desktop-zh.dark` | dark | 91.54 | 99.39 | 92.85 | 98.94 | FAIL | text 2308 px |
| `components.model-retry.started-open-phone-en.light` | light | 93.05 | 99.32 | 94.41 | 96.87 | FAIL | text 4109 px |
| `components.model-retry.started-open-phone-en.dark` | dark | 92.96 | 99.05 | 93.67 | 96.91 | FAIL | text 4249 px |
| `components.model-retry.started-open-phone-zh.light` | light | 92.35 | 99.53 | 94.27 | 95.91 | FAIL | text 3842 px |
| `components.model-retry.started-open-phone-zh.dark` | dark | 92.20 | 99.27 | 93.28 | 95.89 | FAIL | text 3974 px |
| `components.model-retry.cancelled-open-desktop-en.light` | light | 92.12 | 99.71 | 95.65 | 98.83 | FAIL | text 2092 px |
| `components.model-retry.cancelled-open-desktop-en.dark` | dark | 91.97 | 99.44 | 93.20 | 98.76 | FAIL | text 2116 px |
| `components.model-retry.cancelled-open-desktop-zh.light` | light | 91.11 | 99.69 | 94.77 | 98.81 | FAIL | text 2400 px |
| `components.model-retry.cancelled-open-desktop-zh.dark` | dark | 90.84 | 99.36 | 92.28 | 98.88 | FAIL | text 2510 px |
| `components.model-retry.cancelled-open-phone-en.light` | light | 94.26 | 99.43 | 95.38 | 97.45 | FAIL | text 4492 px |
| `components.model-retry.cancelled-open-phone-en.dark` | dark | 94.20 | 99.21 | 94.83 | 97.46 | FAIL | text 4602 px |
| `components.model-retry.cancelled-open-phone-zh.light` | light | 91.73 | 99.48 | 93.71 | 95.69 | FAIL | text 4262 px |
| `components.model-retry.cancelled-open-phone-zh.dark` | dark | 91.57 | 99.20 | 92.74 | 95.64 | FAIL | text 4380 px |
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
| `components.system-prompt.long-open-phone-en.light` | light | 96.05 | 99.60 | 96.97 | 98.37 | basic pass | text 6643 px |
| `components.system-prompt.long-open-phone-en.dark` | dark | 96.04 | 99.44 | 96.54 | 98.35 | basic pass | text 6633 px |
| `components.system-prompt.long-open-phone-zh.light` | light | 96.03 | 99.63 | 96.98 | 98.31 | basic pass | text 6533 px |
| `components.system-prompt.long-open-phone-zh.dark` | dark | 96.02 | 99.47 | 96.54 | 98.30 | basic pass | text 6518 px |
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
| model-retry | 32 | 32 | 0 | 91.84 | 97.53 |
| system-prompt | 40 | 40 | 12 | 95.39 | 98.74 |
