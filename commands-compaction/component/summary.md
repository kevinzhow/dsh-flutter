# dsh-flutter parity: parity-ext

Suite parity-ext: 478 cases in the manifest. all themes, every case (PARITY_EXT_ALL_THEMES=1)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

104 captures: 104 compared, 0 same, 9 pass (official, > 96% pixel-perfect), 13 geometry pass (incl. those), 91 fail, 0 not covered, 0 missing. Mean pixel-perfect 93.38%, mean non-text 97.86%.

## Per case

| case | theme | pixel-perfect % | RGB % | close % | non-text % | status | main bucket |
|---|---|---:|---:|---:|---:|---|---|
| `components.compaction.available-desktop-en.light` | light | 86.96 | 99.56 | 92.86 | 98.47 | FAIL | text 1547 px |
| `components.compaction.available-desktop-en.dark` | dark | 86.38 | 99.21 | 88.95 | 98.50 | FAIL | text 1628 px |
| `components.compaction.available-desktop-zh.light` | light | 86.75 | 99.65 | 92.94 | 97.03 | FAIL | text 1382 px |
| `components.compaction.available-desktop-zh.dark` | dark | 86.32 | 99.27 | 88.77 | 97.09 | FAIL | text 1448 px |
| `components.compaction.available-phone-en.light` | light | 92.89 | 99.33 | 94.23 | 96.97 | FAIL | text 1900 px |
| `components.compaction.available-phone-en.dark` | dark | 92.76 | 99.09 | 93.60 | 96.84 | FAIL | text 1901 px |
| `components.compaction.available-phone-zh.light` | light | 91.50 | 99.47 | 93.76 | 94.97 | FAIL | hairline 1802 px |
| `components.compaction.available-phone-zh.dark` | dark | 91.36 | 99.23 | 92.87 | 94.97 | FAIL | hairline 1800 px |
| `components.compaction.open-desktop-en.light` | light | 92.51 | 98.67 | 94.32 | 98.39 | FAIL | text 2936 px |
| `components.compaction.open-desktop-en.dark` | dark | 92.51 | 98.32 | 93.14 | 98.39 | FAIL | text 2936 px |
| `components.compaction.open-desktop-zh.light` | light | 92.53 | 98.70 | 94.27 | 98.01 | FAIL | text 2739 px |
| `components.compaction.open-desktop-zh.dark` | dark | 92.47 | 98.31 | 93.03 | 98.01 | FAIL | text 2767 px |
| `components.compaction.open-phone-en.light` | light | 93.42 | 97.40 | 93.93 | 97.72 | FAIL | text 7384 px |
| `components.compaction.open-phone-en.dark` | dark | 93.43 | 97.21 | 93.76 | 97.71 | FAIL | text 7350 px |
| `components.compaction.open-phone-zh.light` | light | 93.04 | 97.44 | 93.82 | 97.20 | FAIL | text 7148 px |
| `components.compaction.open-phone-zh.dark` | dark | 93.04 | 97.23 | 93.45 | 97.19 | FAIL | text 7139 px |
| `components.compaction.unavailable-desktop-en.light` | light | 88.54 | 99.65 | 94.31 | 98.57 | FAIL | text 1348 px |
| `components.compaction.unavailable-desktop-en.dark` | dark | 87.92 | 99.34 | 90.19 | 98.63 | FAIL | text 1439 px |
| `components.compaction.unavailable-desktop-zh.light` | light | 91.52 | 99.80 | 95.44 | 97.24 | FAIL | text 769 px |
| `components.compaction.unavailable-desktop-zh.dark` | dark | 91.14 | 99.56 | 93.00 | 97.25 | FAIL | text 821 px |
| `components.compaction.unavailable-phone-en.light` | light | 93.07 | 99.34 | 94.41 | 97.00 | FAIL | text 1834 px |
| `components.compaction.unavailable-phone-en.dark` | dark | 92.94 | 99.11 | 93.75 | 96.88 | FAIL | text 1839 px |
| `components.compaction.unavailable-phone-zh.light` | light | 91.84 | 99.55 | 93.84 | 95.23 | FAIL | hairline 1830 px |
| `components.compaction.unavailable-phone-zh.dark` | dark | 91.70 | 99.32 | 93.23 | 95.18 | FAIL | hairline 1849 px |
| `components.compaction.counts-only-desktop-en.light` | light | 86.96 | 99.56 | 92.86 | 98.47 | FAIL | text 1547 px |
| `components.compaction.counts-only-desktop-en.dark` | dark | 86.38 | 99.21 | 88.95 | 98.50 | FAIL | text 1628 px |
| `components.compaction.counts-only-desktop-zh.light` | light | 86.75 | 99.65 | 92.94 | 97.03 | FAIL | text 1382 px |
| `components.compaction.counts-only-desktop-zh.dark` | dark | 86.32 | 99.27 | 88.77 | 97.09 | FAIL | text 1448 px |
| `components.compaction.counts-only-phone-en.light` | light | 92.89 | 99.33 | 94.23 | 96.97 | FAIL | text 1900 px |
| `components.compaction.counts-only-phone-en.dark` | dark | 92.76 | 99.09 | 93.60 | 96.84 | FAIL | text 1901 px |
| `components.compaction.counts-only-phone-zh.light` | light | 91.50 | 99.47 | 93.76 | 94.97 | FAIL | hairline 1802 px |
| `components.compaction.counts-only-phone-zh.dark` | dark | 91.36 | 99.23 | 92.87 | 94.97 | FAIL | hairline 1800 px |
| `components.compaction.manual-open-desktop-en.light` | light | 93.22 | 98.70 | 94.73 | 98.55 | FAIL | text 2660 px |
| `components.compaction.manual-open-desktop-en.dark` | dark | 93.21 | 98.38 | 93.74 | 98.56 | FAIL | text 2668 px |
| `components.compaction.manual-open-desktop-zh.light` | light | 92.99 | 98.70 | 94.47 | 98.27 | FAIL | text 2633 px |
| `components.compaction.manual-open-desktop-zh.dark` | dark | 92.96 | 98.36 | 93.44 | 98.28 | FAIL | text 2656 px |
| `components.compaction.manual-open-phone-en.light` | light | 93.48 | 97.41 | 93.99 | 97.76 | FAIL | text 7358 px |
| `components.compaction.manual-open-phone-en.dark` | dark | 93.49 | 97.22 | 93.80 | 97.75 | FAIL | text 7337 px |
| `components.compaction.manual-open-phone-zh.light` | light | 93.20 | 97.44 | 93.99 | 97.45 | FAIL | text 7307 px |
| `components.compaction.manual-open-phone-zh.dark` | dark | 93.20 | 97.23 | 93.55 | 97.43 | FAIL | text 7274 px |
| `components.compaction.manual-fallback-desktop-en.light` | light | 93.85 | 99.83 | 97.04 | 99.17 | FAIL | text 716 px |
| `components.compaction.manual-fallback-desktop-en.dark` | dark | 93.59 | 99.67 | 94.83 | 99.19 | FAIL | text 752 px |
| `components.compaction.manual-fallback-desktop-zh.light` | light | 93.85 | 99.83 | 97.04 | 99.17 | FAIL | text 716 px |
| `components.compaction.manual-fallback-desktop-zh.dark` | dark | 93.59 | 99.67 | 94.83 | 99.19 | FAIL | text 752 px |
| `components.compaction.manual-fallback-phone-en.light` | light | 93.66 | 99.41 | 94.88 | 96.94 | FAIL | text 1526 px |
| `components.compaction.manual-fallback-phone-en.dark` | dark | 93.53 | 99.19 | 94.18 | 96.84 | FAIL | text 1544 px |
| `components.compaction.manual-fallback-phone-zh.light` | light | 93.66 | 99.41 | 94.88 | 96.94 | FAIL | text 1526 px |
| `components.compaction.manual-fallback-phone-zh.dark` | dark | 93.53 | 99.19 | 94.18 | 96.84 | FAIL | text 1544 px |
| `components.command.running-desktop-en.light` | light | 96.02 | 99.88 | 97.94 | 99.66 | basic pass | text 420 px |
| `components.command.running-desktop-en.dark` | dark | 95.77 | 99.76 | 96.47 | 99.69 | geometry pass | text 451 px |
| `components.command.running-desktop-zh.light` | light | 96.07 | 99.90 | 97.92 | 99.53 | basic pass | text 399 px |
| `components.command.running-desktop-zh.dark` | dark | 95.75 | 99.79 | 96.75 | 99.52 | geometry pass | text 434 px |
| `components.command.running-phone-en.light` | light | 95.70 | 99.62 | 96.81 | 97.73 | FAIL | hairline 846 px |
| `components.command.running-phone-en.dark` | dark | 95.60 | 99.48 | 96.14 | 97.78 | FAIL | text 865 px |
| `components.command.running-phone-zh.light` | light | 96.14 | 99.75 | 97.43 | 98.18 | basic pass | text 810 px |
| `components.command.running-phone-zh.dark` | dark | 95.95 | 99.63 | 96.68 | 98.12 | FAIL | text 863 px |
| `components.command.success-desktop-en.light` | light | 95.63 | 99.86 | 97.60 | 99.44 | FAIL | text 438 px |
| `components.command.success-desktop-en.dark` | dark | 95.42 | 99.74 | 96.26 | 99.46 | FAIL | text 466 px |
| `components.command.success-desktop-zh.light` | light | 95.63 | 99.86 | 97.60 | 99.44 | FAIL | text 438 px |
| `components.command.success-desktop-zh.dark` | dark | 95.42 | 99.74 | 96.26 | 99.46 | FAIL | text 466 px |
| `components.command.success-phone-en.light` | light | 95.53 | 99.56 | 96.40 | 97.92 | FAIL | text 949 px |
| `components.command.success-phone-en.dark` | dark | 95.42 | 99.41 | 95.91 | 97.94 | FAIL | text 1001 px |
| `components.command.success-phone-zh.light` | light | 95.53 | 99.56 | 96.40 | 97.92 | FAIL | text 949 px |
| `components.command.success-phone-zh.dark` | dark | 95.42 | 99.41 | 95.91 | 97.94 | FAIL | text 1001 px |
| `components.command.success-open-desktop-en.light` | light | 96.13 | 99.46 | 97.07 | 99.32 | basic pass | text 1377 px |
| `components.command.success-open-desktop-en.dark` | dark | 93.84 | 99.27 | 96.57 | 97.02 | FAIL | text 1374 px |
| `components.command.success-open-desktop-zh.light` | light | 96.13 | 99.46 | 97.07 | 99.32 | basic pass | text 1377 px |
| `components.command.success-open-desktop-zh.dark` | dark | 93.84 | 99.27 | 96.57 | 97.02 | FAIL | text 1374 px |
| `components.command.success-open-phone-en.light` | light | 95.48 | 98.97 | 96.34 | 98.10 | FAIL | text 3845 px |
| `components.command.success-open-phone-en.dark` | dark | 94.97 | 98.73 | 96.11 | 97.59 | FAIL | text 3844 px |
| `components.command.success-open-phone-zh.light` | light | 95.48 | 98.97 | 96.34 | 98.10 | FAIL | text 3845 px |
| `components.command.success-open-phone-zh.dark` | dark | 94.97 | 98.73 | 96.11 | 97.59 | FAIL | text 3844 px |
| `components.command.error-open-desktop-en.light` | light | 96.70 | 99.59 | 97.38 | 99.35 | basic pass | text 1144 px |
| `components.command.error-open-desktop-en.dark` | dark | 94.42 | 99.71 | 97.57 | 97.04 | FAIL | hairline 1178 px |
| `components.command.error-open-desktop-zh.light` | light | 96.70 | 99.59 | 97.38 | 99.35 | basic pass | text 1144 px |
| `components.command.error-open-desktop-zh.dark` | dark | 94.42 | 99.71 | 97.57 | 97.04 | FAIL | hairline 1178 px |
| `components.command.error-open-phone-en.light` | light | 96.20 | 99.20 | 96.85 | 98.00 | basic pass | text 2644 px |
| `components.command.error-open-phone-en.dark` | dark | 95.68 | 99.40 | 97.07 | 97.48 | FAIL | hairline 3325 px |
| `components.command.error-open-phone-zh.light` | light | 96.20 | 99.20 | 96.85 | 98.00 | basic pass | text 2644 px |
| `components.command.error-open-phone-zh.dark` | dark | 95.68 | 99.40 | 97.07 | 97.48 | FAIL | hairline 3325 px |
| `components.command.orphan-desktop-en.light` | light | 93.03 | 99.63 | 95.01 | 99.16 | FAIL | text 706 px |
| `components.command.orphan-desktop-en.dark` | dark | 92.86 | 99.74 | 94.81 | 99.12 | FAIL | text 721 px |
| `components.command.orphan-desktop-zh.light` | light | 94.87 | 99.76 | 96.11 | 99.81 | geometry pass | text 569 px |
| `components.command.orphan-desktop-zh.dark` | dark | 94.79 | 99.84 | 96.44 | 99.81 | geometry pass | text 578 px |
| `components.command.orphan-phone-en.light` | light | 93.08 | 99.27 | 94.24 | 96.60 | FAIL | text 1396 px |
| `components.command.orphan-phone-en.dark` | dark | 92.96 | 99.35 | 94.18 | 96.53 | FAIL | text 1418 px |
| `components.command.orphan-phone-zh.light` | light | 95.12 | 99.66 | 96.03 | 97.91 | FAIL | text 1104 px |
| `components.command.orphan-phone-zh.dark` | dark | 95.10 | 99.76 | 96.28 | 97.90 | FAIL | text 1111 px |
| `components.command.manual-running-desktop-en.light` | light | 92.46 | 99.78 | 96.08 | 99.28 | FAIL | text 786 px |
| `components.command.manual-running-desktop-en.dark` | dark | 92.00 | 99.58 | 93.52 | 99.33 | FAIL | text 844 px |
| `components.command.manual-running-desktop-zh.light` | light | 94.27 | 99.86 | 97.27 | 98.60 | FAIL | text 499 px |
| `components.command.manual-running-desktop-zh.dark` | dark | 94.01 | 99.72 | 95.33 | 98.58 | FAIL | text 527 px |
| `components.command.manual-running-phone-en.light` | light | 92.37 | 99.29 | 93.89 | 96.76 | FAIL | text 1744 px |
| `components.command.manual-running-phone-en.dark` | dark | 92.19 | 99.03 | 93.13 | 96.67 | FAIL | text 1777 px |
| `components.command.manual-running-phone-zh.light` | light | 94.40 | 99.63 | 95.85 | 97.10 | FAIL | text 1070 px |
| `components.command.manual-running-phone-zh.dark` | dark | 94.27 | 99.46 | 95.08 | 96.93 | FAIL | hairline 1065 px |
| `components.command.manual-error-open-desktop-en.light` | light | 95.57 | 99.57 | 96.42 | 99.24 | FAIL | text 1582 px |
| `components.command.manual-error-open-desktop-en.dark` | dark | 93.27 | 99.71 | 96.96 | 96.91 | FAIL | text 1573 px |
| `components.command.manual-error-open-desktop-zh.light` | light | 95.57 | 99.57 | 96.42 | 99.24 | FAIL | text 1582 px |
| `components.command.manual-error-open-desktop-zh.dark` | dark | 93.27 | 99.71 | 96.96 | 96.91 | FAIL | text 1573 px |
| `components.command.manual-error-open-phone-en.light` | light | 95.70 | 99.44 | 96.49 | 97.89 | FAIL | text 3223 px |
| `components.command.manual-error-open-phone-en.dark` | dark | 95.16 | 99.56 | 96.68 | 97.35 | FAIL | hairline 3520 px |
| `components.command.manual-error-open-phone-zh.light` | light | 95.70 | 99.44 | 96.49 | 97.89 | FAIL | text 3223 px |
| `components.command.manual-error-open-phone-zh.dark` | dark | 95.16 | 99.56 | 96.68 | 97.35 | FAIL | hairline 3520 px |

## Per area

| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |
|---|---:|---:|---:|---:|---:|
| compaction | 48 | 48 | 0 | 91.59 | 97.43 |
| command | 56 | 56 | 13 | 94.91 | 98.22 |
