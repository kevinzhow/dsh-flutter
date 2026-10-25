# dsh-flutter parity: parity-ext

Suite parity-ext: 1182 cases in the manifest. all themes, every case (PARITY_EXT_ALL_THEMES=1)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

168 captures: 168 compared, 0 same, 2 pass (official, > 96% pixel-perfect), 2 geometry pass (incl. those), 166 fail, 0 not covered, 0 missing. Mean pixel-perfect 72.66%, mean non-text 79.31%.

## Per case

| case | theme | pixel-perfect % | RGB % | close % | non-text % | status | main bucket |
|---|---|---:|---:|---:|---:|---|---|
| `components.workspace-management.row-idle-desktop-en.light` | light | 90.70 | 98.72 | 92.06 | 98.23 | FAIL | text 617 px |
| `components.workspace-management.row-idle-desktop-en.dark` | dark | 90.70 | 98.45 | 91.42 | 98.08 | FAIL | text 605 px |
| `components.workspace-management.row-idle-desktop-zh.light` | light | 89.99 | 98.70 | 91.54 | 98.47 | FAIL | text 695 px |
| `components.workspace-management.row-idle-desktop-zh.dark` | dark | 89.92 | 98.40 | 90.75 | 98.33 | FAIL | text 689 px |
| `components.workspace-management.row-idle-phone-en.light` | light | 96.31 | 97.92 | 96.80 | 98.32 | FAIL | text 1143 px |
| `components.workspace-management.row-idle-phone-en.dark` | dark | 95.12 | 97.88 | 95.63 | 97.10 | FAIL | hairline 1641 px |
| `components.workspace-management.row-idle-phone-zh.light` | light | 95.86 | 97.77 | 96.52 | 98.40 | FAIL | text 1450 px |
| `components.workspace-management.row-idle-phone-zh.dark` | dark | 94.68 | 97.69 | 95.23 | 97.22 | FAIL | hairline 1556 px |
| `components.workspace-management.row-hover-desktop-en.light` | light | 89.06 | 98.87 | 91.99 | 96.12 | FAIL | text 578 px |
| `components.workspace-management.row-hover-desktop-en.dark` | dark | 1.22 | 98.35 | 91.80 | 19.25 | FAIL | fill 5812 px |
| `components.workspace-management.row-hover-desktop-zh.light` | light | 89.06 | 98.87 | 91.99 | 96.12 | FAIL | text 578 px |
| `components.workspace-management.row-hover-desktop-zh.dark` | dark | 1.22 | 98.35 | 91.80 | 19.25 | FAIL | fill 5812 px |
| `components.workspace-management.row-hover-phone-en.light` | light | 94.86 | 97.73 | 95.54 | 97.19 | FAIL | text 1330 px |
| `components.workspace-management.row-hover-phone-en.dark` | dark | 3.36 | 97.38 | 94.43 | 12.81 | FAIL | fill 47629 px |
| `components.workspace-management.row-hover-phone-zh.light` | light | 94.86 | 97.73 | 95.54 | 97.19 | FAIL | text 1330 px |
| `components.workspace-management.row-hover-phone-zh.dark` | dark | 3.36 | 97.38 | 94.43 | 12.81 | FAIL | fill 47629 px |
| `components.workspace-management.row-pinned-desktop-en.light` | light | 90.03 | 98.69 | 91.65 | 98.23 | FAIL | text 672 px |
| `components.workspace-management.row-pinned-desktop-en.dark` | dark | 90.02 | 98.40 | 90.99 | 98.08 | FAIL | text 661 px |
| `components.workspace-management.row-pinned-desktop-zh.light` | light | 89.32 | 98.66 | 91.12 | 98.47 | FAIL | text 750 px |
| `components.workspace-management.row-pinned-desktop-zh.dark` | dark | 89.23 | 98.35 | 90.32 | 98.33 | FAIL | text 745 px |
| `components.workspace-management.row-pinned-phone-en.light` | light | 95.85 | 97.86 | 96.51 | 98.19 | FAIL | text 1338 px |
| `components.workspace-management.row-pinned-phone-en.dark` | dark | 94.64 | 97.79 | 95.25 | 97.02 | FAIL | hairline 1645 px |
| `components.workspace-management.row-pinned-phone-zh.light` | light | 95.39 | 97.70 | 96.20 | 98.31 | FAIL | text 1669 px |
| `components.workspace-management.row-pinned-phone-zh.dark` | dark | 94.20 | 97.58 | 94.88 | 97.18 | FAIL | text 1702 px |
| `components.workspace-management.row-archived-desktop-en.light` | light | 90.87 | 99.51 | 93.63 | 98.05 | FAIL | text 588 px |
| `components.workspace-management.row-archived-desktop-en.dark` | dark | 90.91 | 99.32 | 92.76 | 98.07 | FAIL | text 587 px |
| `components.workspace-management.row-archived-desktop-zh.light` | light | 90.16 | 99.49 | 93.10 | 98.29 | FAIL | text 666 px |
| `components.workspace-management.row-archived-desktop-zh.dark` | dark | 90.12 | 99.27 | 92.09 | 98.31 | FAIL | text 671 px |
| `components.workspace-management.row-archived-phone-en.light` | light | 96.49 | 99.22 | 97.69 | 98.35 | FAIL | text 1063 px |
| `components.workspace-management.row-archived-phone-en.dark` | dark | 95.18 | 98.85 | 96.32 | 97.10 | FAIL | hairline 1639 px |
| `components.workspace-management.row-archived-phone-zh.light` | light | 96.03 | 99.06 | 97.41 | 98.43 | FAIL | text 1370 px |
| `components.workspace-management.row-archived-phone-zh.dark` | dark | 94.75 | 98.65 | 95.92 | 97.22 | FAIL | hairline 1554 px |
| `components.workspace-management.row-running-desktop-en.light` | light | 89.92 | 98.71 | 91.82 | 97.81 | FAIL | text 647 px |
| `components.workspace-management.row-running-desktop-en.dark` | dark | 89.76 | 98.44 | 91.14 | 97.55 | FAIL | text 638 px |
| `components.workspace-management.row-running-desktop-zh.light` | light | 89.21 | 98.69 | 91.30 | 98.06 | FAIL | text 725 px |
| `components.workspace-management.row-running-desktop-zh.dark` | dark | 88.98 | 98.39 | 90.47 | 97.79 | FAIL | text 722 px |
| `components.workspace-management.row-running-phone-en.light` | light | 95.70 | 97.84 | 96.50 | 97.90 | FAIL | text 1254 px |
| `components.workspace-management.row-running-phone-en.dark` | dark | 94.52 | 97.77 | 95.31 | 96.69 | FAIL | hairline 1714 px |
| `components.workspace-management.row-running-phone-zh.light` | light | 95.25 | 97.69 | 96.22 | 97.98 | FAIL | text 1561 px |
| `components.workspace-management.row-running-phone-zh.dark` | dark | 94.08 | 97.57 | 94.91 | 96.81 | FAIL | hairline 1629 px |
| `components.workspace-management.row-pending-desktop-en.light` | light | 89.92 | 98.68 | 91.32 | 98.47 | FAIL | text 701 px |
| `components.workspace-management.row-pending-desktop-en.dark` | dark | 89.80 | 98.39 | 90.94 | 98.33 | FAIL | text 699 px |
| `components.workspace-management.row-pending-desktop-zh.light` | light | 89.34 | 98.79 | 91.54 | 97.97 | FAIL | text 707 px |
| `components.workspace-management.row-pending-desktop-zh.dark` | dark | 89.14 | 98.49 | 90.41 | 97.77 | FAIL | text 707 px |
| `components.workspace-management.row-pending-phone-en.light` | light | 95.90 | 97.81 | 96.62 | 98.39 | FAIL | text 1418 px |
| `components.workspace-management.row-pending-phone-en.dark` | dark | 94.72 | 97.74 | 95.33 | 97.21 | FAIL | hairline 1561 px |
| `components.workspace-management.row-pending-phone-zh.light` | light | 95.59 | 97.63 | 96.54 | 97.93 | FAIL | text 1339 px |
| `components.workspace-management.row-pending-phone-zh.dark` | dark | 94.41 | 97.51 | 95.21 | 96.75 | FAIL | hairline 1735 px |
| `components.workspace-management.row-long-desktop-en.light` | light | 87.82 | 98.74 | 90.94 | 94.92 | FAIL | text 582 px |
| `components.workspace-management.row-long-desktop-en.dark` | dark | 1.33 | 98.18 | 90.50 | 21.66 | FAIL | fill 5614 px |
| `components.workspace-management.row-long-desktop-zh.light` | light | 87.82 | 98.74 | 90.94 | 94.92 | FAIL | text 582 px |
| `components.workspace-management.row-long-desktop-zh.dark` | dark | 1.33 | 98.18 | 90.50 | 21.66 | FAIL | fill 5614 px |
| `components.workspace-management.row-long-phone-en.light` | light | 93.72 | 97.18 | 94.35 | 96.70 | FAIL | text 1703 px |
| `components.workspace-management.row-long-phone-en.dark` | dark | 3.64 | 96.91 | 93.27 | 14.48 | FAIL | fill 46574 px |
| `components.workspace-management.row-long-phone-zh.light` | light | 93.72 | 97.18 | 94.35 | 96.70 | FAIL | text 1703 px |
| `components.workspace-management.row-long-phone-zh.dark` | dark | 3.64 | 96.91 | 93.27 | 14.48 | FAIL | fill 46574 px |
| `components.workspace-management.menu-idle-desktop-en.light` | light | 0.25 | 93.28 | 1.40 | 16.42 | FAIL | other 14090 px |
| `components.workspace-management.menu-idle-desktop-en.dark` | dark | 0.28 | 93.30 | 1.31 | 19.40 | FAIL | other 17556 px |
| `components.workspace-management.menu-idle-desktop-zh.light` | light | 0.04 | 93.27 | 1.17 | 16.32 | FAIL | other 13979 px |
| `components.workspace-management.menu-idle-desktop-zh.dark` | dark | 0.06 | 93.17 | 0.96 | 17.91 | FAIL | other 17776 px |
| `components.workspace-management.menu-idle-phone-en.light` | light | 2.14 | 91.76 | 2.54 | 12.52 | FAIL | other 141883 px |
| `components.workspace-management.menu-idle-phone-en.dark` | dark | 2.17 | 92.47 | 2.97 | 13.81 | FAIL | other 145164 px |
| `components.workspace-management.menu-idle-phone-zh.light` | light | 1.93 | 91.14 | 2.42 | 11.38 | FAIL | other 142322 px |
| `components.workspace-management.menu-idle-phone-zh.dark` | dark | 1.95 | 91.91 | 2.63 | 12.51 | FAIL | other 145887 px |
| `components.workspace-management.menu-pinned-desktop-en.light` | light | 0.27 | 93.25 | 1.39 | 16.90 | FAIL | other 14270 px |
| `components.workspace-management.menu-pinned-desktop-en.dark` | dark | 0.30 | 93.26 | 1.36 | 20.14 | FAIL | other 17522 px |
| `components.workspace-management.menu-pinned-desktop-zh.light` | light | 0.14 | 93.25 | 1.31 | 16.16 | FAIL | other 14302 px |
| `components.workspace-management.menu-pinned-desktop-zh.dark` | dark | 0.16 | 93.16 | 1.05 | 18.02 | FAIL | other 17906 px |
| `components.workspace-management.menu-pinned-phone-en.light` | light | 2.27 | 91.68 | 2.71 | 12.90 | FAIL | other 141900 px |
| `components.workspace-management.menu-pinned-phone-en.dark` | dark | 2.33 | 92.40 | 3.13 | 14.32 | FAIL | other 144055 px |
| `components.workspace-management.menu-pinned-phone-zh.light` | light | 2.00 | 91.17 | 2.53 | 11.48 | FAIL | other 142523 px |
| `components.workspace-management.menu-pinned-phone-zh.dark` | dark | 2.06 | 91.93 | 2.73 | 12.63 | FAIL | other 145822 px |
| `components.workspace-management.menu-archived-desktop-en.light` | light | 0.02 | 91.10 | 1.15 | 16.40 | FAIL | other 12848 px |
| `components.workspace-management.menu-archived-desktop-en.dark` | dark | 0.04 | 91.41 | 0.80 | 18.96 | FAIL | other 16055 px |
| `components.workspace-management.menu-archived-desktop-zh.light` | light | 0.06 | 93.55 | 1.31 | 15.93 | FAIL | other 12019 px |
| `components.workspace-management.menu-archived-desktop-zh.dark` | dark | 0.08 | 93.46 | 1.05 | 18.49 | FAIL | other 15344 px |
| `components.workspace-management.menu-archived-phone-en.light` | light | 2.44 | 92.05 | 2.90 | 12.78 | FAIL | other 123894 px |
| `components.workspace-management.menu-archived-phone-en.dark` | dark | 2.29 | 92.73 | 3.27 | 13.68 | FAIL | other 126184 px |
| `components.workspace-management.menu-archived-phone-zh.light` | light | 1.73 | 92.04 | 2.59 | 11.75 | FAIL | other 116304 px |
| `components.workspace-management.menu-archived-phone-zh.dark` | dark | 1.75 | 92.67 | 2.50 | 12.68 | FAIL | other 118533 px |
| `components.workspace-management.hover-idle-desktop-en.light` | light | 94.16 | 99.05 | 94.88 | 98.66 | FAIL | text 1052 px |
| `components.workspace-management.hover-idle-desktop-en.dark` | dark | 94.22 | 99.33 | 95.29 | 97.82 | FAIL | text 845 px |
| `components.workspace-management.hover-idle-desktop-zh.light` | light | 93.44 | 98.75 | 94.27 | 98.51 | FAIL | text 1188 px |
| `components.workspace-management.hover-idle-desktop-zh.dark` | dark | 93.49 | 99.02 | 94.68 | 97.68 | FAIL | text 981 px |
| `components.workspace-management.hover-idle-phone-en.light` | light | 94.73 | 97.73 | 95.50 | 97.40 | FAIL | text 1949 px |
| `components.workspace-management.hover-idle-phone-en.dark` | dark | 94.80 | 98.29 | 95.92 | 96.70 | FAIL | hairline 1650 px |
| `components.workspace-management.hover-idle-phone-zh.light` | light | 92.93 | 96.87 | 93.63 | 97.12 | FAIL | text 3067 px |
| `components.workspace-management.hover-idle-phone-zh.dark` | dark | 93.00 | 97.43 | 94.05 | 96.42 | FAIL | text 2505 px |
| `components.workspace-management.hover-archived-desktop-en.light` | light | 92.57 | 98.58 | 93.28 | 97.87 | FAIL | text 1242 px |
| `components.workspace-management.hover-archived-desktop-en.dark` | dark | 92.60 | 98.86 | 93.69 | 97.11 | FAIL | text 1055 px |
| `components.workspace-management.hover-archived-desktop-zh.light` | light | 92.07 | 98.28 | 92.79 | 97.65 | FAIL | text 1307 px |
| `components.workspace-management.hover-archived-desktop-zh.dark` | dark | 92.11 | 98.55 | 93.20 | 96.89 | FAIL | text 1120 px |
| `components.workspace-management.hover-archived-phone-en.light` | light | 92.00 | 96.68 | 92.78 | 96.13 | FAIL | text 3020 px |
| `components.workspace-management.hover-archived-phone-en.dark` | dark | 92.07 | 97.22 | 93.18 | 95.53 | FAIL | text 2532 px |
| `components.workspace-management.hover-archived-phone-zh.light` | light | 90.48 | 95.97 | 91.11 | 94.87 | FAIL | text 3208 px |
| `components.workspace-management.hover-archived-phone-zh.dark` | dark | 90.54 | 96.50 | 91.51 | 94.26 | FAIL | text 2720 px |
| `components.workspace-management.hover-running-desktop-en.light` | light | 93.40 | 99.00 | 94.35 | 98.38 | FAIL | text 1167 px |
| `components.workspace-management.hover-running-desktop-en.dark` | dark | 93.43 | 99.28 | 94.74 | 97.60 | FAIL | text 976 px |
| `components.workspace-management.hover-running-desktop-zh.light` | light | 93.05 | 98.73 | 93.93 | 98.59 | FAIL | text 1299 px |
| `components.workspace-management.hover-running-desktop-zh.dark` | dark | 93.08 | 99.01 | 94.32 | 97.81 | FAIL | text 1108 px |
| `components.workspace-management.hover-running-phone-en.light` | light | 93.91 | 97.56 | 95.10 | 96.73 | FAIL | text 2056 px |
| `components.workspace-management.hover-running-phone-en.dark` | dark | 94.13 | 98.07 | 95.47 | 96.26 | FAIL | hairline 1944 px |
| `components.workspace-management.hover-running-phone-zh.light` | light | 92.45 | 96.77 | 93.49 | 96.78 | FAIL | text 3165 px |
| `components.workspace-management.hover-running-phone-zh.dark` | dark | 92.66 | 97.29 | 93.86 | 96.31 | FAIL | text 2670 px |
| `components.workspace-management.group-idle-desktop-en.light` | light | 92.14 | 98.91 | 93.36 | 98.03 | FAIL | text 513 px |
| `components.workspace-management.group-idle-desktop-en.dark` | dark | 91.83 | 98.70 | 93.23 | 97.88 | FAIL | text 526 px |
| `components.workspace-management.group-idle-desktop-zh.light` | light | 92.14 | 98.91 | 93.36 | 98.03 | FAIL | text 513 px |
| `components.workspace-management.group-idle-desktop-zh.dark` | dark | 91.83 | 98.70 | 93.23 | 97.88 | FAIL | text 526 px |
| `components.workspace-management.group-idle-phone-en.light` | light | 96.00 | 98.93 | 96.30 | 98.15 | basic pass | text 1299 px |
| `components.workspace-management.group-idle-phone-en.dark` | dark | 95.93 | 98.89 | 96.34 | 98.12 | FAIL | text 1327 px |
| `components.workspace-management.group-idle-phone-zh.light` | light | 96.00 | 98.93 | 96.30 | 98.15 | basic pass | text 1299 px |
| `components.workspace-management.group-idle-phone-zh.dark` | dark | 95.93 | 98.89 | 96.34 | 98.12 | FAIL | text 1327 px |
| `components.workspace-management.group-hover-desktop-en.light` | light | 88.64 | 98.47 | 90.30 | 96.46 | FAIL | text 681 px |
| `components.workspace-management.group-hover-desktop-en.dark` | dark | 1.41 | 97.83 | 90.03 | 19.89 | FAIL | fill 6147 px |
| `components.workspace-management.group-hover-desktop-zh.light` | light | 88.64 | 98.47 | 90.30 | 96.46 | FAIL | text 681 px |
| `components.workspace-management.group-hover-desktop-zh.dark` | dark | 1.41 | 97.83 | 90.03 | 19.89 | FAIL | fill 6147 px |
| `components.workspace-management.group-hover-phone-en.light` | light | 92.57 | 98.39 | 93.01 | 95.53 | FAIL | hairline 2094 px |
| `components.workspace-management.group-hover-phone-en.dark` | dark | 2.88 | 97.85 | 93.01 | 11.77 | FAIL | fill 50111 px |
| `components.workspace-management.group-hover-phone-zh.light` | light | 92.57 | 98.39 | 93.01 | 95.53 | FAIL | hairline 2094 px |
| `components.workspace-management.group-hover-phone-zh.dark` | dark | 2.88 | 97.85 | 93.01 | 11.77 | FAIL | fill 50111 px |
| `components.workspace-management.rename-ready-desktop-en.light` | light | 91.17 | 98.42 | 91.83 | 95.58 | FAIL | text 3453 px |
| `components.workspace-management.rename-ready-desktop-en.dark` | dark | 90.97 | 98.46 | 92.00 | 94.63 | FAIL | text 2867 px |
| `components.workspace-management.rename-ready-desktop-zh.light` | light | 91.23 | 98.49 | 91.88 | 95.79 | FAIL | text 3569 px |
| `components.workspace-management.rename-ready-desktop-zh.dark` | dark | 91.06 | 98.56 | 92.00 | 94.77 | FAIL | text 2906 px |
| `components.workspace-management.rename-ready-phone-en.light` | light | 92.81 | 98.39 | 93.31 | 96.29 | FAIL | text 16878 px |
| `components.workspace-management.rename-ready-phone-en.dark` | dark | 92.74 | 98.49 | 93.43 | 95.78 | FAIL | text 14755 px |
| `components.workspace-management.rename-ready-phone-zh.light` | light | 92.97 | 98.45 | 93.47 | 96.20 | FAIL | text 15666 px |
| `components.workspace-management.rename-ready-phone-zh.dark` | dark | 92.91 | 98.57 | 93.60 | 95.68 | FAIL | text 13470 px |
| `components.workspace-management.rename-pending-desktop-en.light` | light | 88.91 | 98.37 | 92.85 | 93.34 | FAIL | text 3463 px |
| `components.workspace-management.rename-pending-desktop-en.dark` | dark | 88.65 | 98.79 | 93.00 | 92.30 | FAIL | text 2855 px |
| `components.workspace-management.rename-pending-desktop-zh.light` | light | 89.44 | 98.39 | 92.82 | 93.93 | FAIL | text 3514 px |
| `components.workspace-management.rename-pending-desktop-zh.dark` | dark | 89.23 | 98.83 | 92.88 | 92.93 | FAIL | text 2896 px |
| `components.workspace-management.rename-pending-phone-en.light` | light | 90.09 | 98.34 | 94.53 | 92.91 | FAIL | fill 17289 px |
| `components.workspace-management.rename-pending-phone-en.dark` | dark | 90.90 | 98.81 | 94.42 | 93.49 | FAIL | fill 13294 px |
| `components.workspace-management.rename-pending-phone-zh.light` | light | 90.79 | 98.35 | 94.56 | 93.22 | FAIL | fill 14190 px |
| `components.workspace-management.rename-pending-phone-zh.dark` | dark | 93.59 | 98.84 | 94.48 | 95.61 | FAIL | text 9813 px |
| `components.workspace-management.rename-refused-desktop-en.light` | light | 90.67 | 98.37 | 91.38 | 94.76 | FAIL | text 3606 px |
| `components.workspace-management.rename-refused-desktop-en.dark` | dark | 90.50 | 98.85 | 91.60 | 94.16 | FAIL | text 3228 px |
| `components.workspace-management.rename-refused-desktop-zh.light` | light | 91.17 | 98.54 | 91.93 | 95.28 | FAIL | text 3621 px |
| `components.workspace-management.rename-refused-desktop-zh.dark` | dark | 91.03 | 98.94 | 92.04 | 94.67 | FAIL | text 3213 px |
| `components.workspace-management.rename-refused-phone-en.light` | light | 92.43 | 98.33 | 92.88 | 94.85 | FAIL | other 17068 px |
| `components.workspace-management.rename-refused-phone-en.dark` | dark | 92.43 | 98.96 | 93.06 | 94.69 | FAIL | other 16204 px |
| `components.workspace-management.rename-refused-phone-zh.light` | light | 93.10 | 98.50 | 93.56 | 95.13 | FAIL | other 14052 px |
| `components.workspace-management.rename-refused-phone-zh.dark` | dark | 93.10 | 99.04 | 93.73 | 94.96 | FAIL | other 13225 px |
| `components.workspace-management.archive-ready-desktop-en.light` | light | 90.04 | 98.69 | 91.25 | 97.47 | FAIL | text 9043 px |
| `components.workspace-management.archive-ready-desktop-en.dark` | dark | 89.69 | 98.69 | 91.40 | 96.73 | FAIL | text 8563 px |
| `components.workspace-management.archive-ready-desktop-zh.light` | light | 89.48 | 98.89 | 90.79 | 97.01 | FAIL | text 7896 px |
| `components.workspace-management.archive-ready-desktop-zh.dark` | dark | 89.15 | 98.84 | 90.62 | 96.33 | FAIL | text 7536 px |
| `components.workspace-management.archive-ready-phone-en.light` | light | 93.97 | 97.98 | 94.60 | 97.52 | FAIL | text 26748 px |
| `components.workspace-management.archive-ready-phone-en.dark` | dark | 93.82 | 98.23 | 94.67 | 97.26 | FAIL | text 25950 px |
| `components.workspace-management.archive-ready-phone-zh.light` | light | 94.32 | 99.15 | 94.89 | 96.61 | FAIL | hairline 17296 px |
| `components.workspace-management.archive-ready-phone-zh.dark` | dark | 94.28 | 99.25 | 95.01 | 96.44 | FAIL | hairline 17714 px |
| `components.workspace-management.archive-pending-desktop-en.light` | light | 90.02 | 98.75 | 91.43 | 97.55 | FAIL | text 9667 px |
| `components.workspace-management.archive-pending-desktop-en.dark` | dark | 89.70 | 98.70 | 91.38 | 96.85 | FAIL | text 9180 px |
| `components.workspace-management.archive-pending-desktop-zh.light` | light | 89.67 | 98.96 | 91.10 | 97.09 | FAIL | text 8297 px |
| `components.workspace-management.archive-pending-desktop-zh.dark` | dark | 89.31 | 98.86 | 90.62 | 96.45 | FAIL | text 7982 px |
| `components.workspace-management.archive-pending-phone-en.light` | light | 93.00 | 98.24 | 93.77 | 97.22 | FAIL | text 33708 px |
| `components.workspace-management.archive-pending-phone-en.dark` | dark | 93.10 | 98.44 | 93.93 | 97.11 | FAIL | text 31952 px |
| `components.workspace-management.archive-pending-phone-zh.light` | light | 93.40 | 98.16 | 94.08 | 96.39 | FAIL | text 22326 px |
| `components.workspace-management.archive-pending-phone-zh.dark` | dark | 93.42 | 98.38 | 94.20 | 96.30 | FAIL | text 21459 px |
| `components.workspace-management.archive-refused-desktop-en.light` | light | 87.15 | 98.59 | 88.22 | 95.05 | FAIL | text 10394 px |
| `components.workspace-management.archive-refused-desktop-en.dark` | dark | 87.05 | 98.56 | 88.40 | 94.56 | FAIL | text 9886 px |
| `components.workspace-management.archive-refused-desktop-zh.light` | light | 87.42 | 98.81 | 88.54 | 95.27 | FAIL | text 9011 px |
| `components.workspace-management.archive-refused-desktop-zh.dark` | dark | 87.29 | 98.74 | 88.40 | 94.77 | FAIL | text 8584 px |
| `components.workspace-management.archive-refused-phone-en.light` | light | 90.83 | 99.00 | 91.40 | 94.33 | FAIL | other 29531 px |
| `components.workspace-management.archive-refused-phone-en.dark` | dark | 90.85 | 99.08 | 91.62 | 94.21 | FAIL | other 28890 px |
| `components.workspace-management.archive-refused-phone-zh.light` | light | 91.94 | 99.08 | 92.45 | 94.62 | FAIL | text 20492 px |
| `components.workspace-management.archive-refused-phone-zh.dark` | dark | 91.96 | 99.12 | 92.60 | 94.44 | FAIL | other 19686 px |

## Per area

| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |
|---|---:|---:|---:|---:|---:|
| workspace-management | 168 | 168 | 2 | 72.66 | 79.31 |
