# dsh-flutter parity: parity-ext

Suite parity-ext: 334 cases in the manifest. all themes, every case (PARITY_EXT_ALL_THEMES=1)

pixel-perfect and RGB similarity are the vendored visual-testing CLI's (status: pass > 99%, basic pass > 96% pixel-perfect); non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= 99.5%); close = within 4/255 per channel.

32 captures: 32 compared, 0 same, 0 pass (official, > 96% pixel-perfect), 0 geometry pass (incl. those), 32 fail, 0 not covered, 0 missing. Mean pixel-perfect 91.74%, mean non-text 97.51%.

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
| `components.model-retry.started-open-desktop-zh.light` | light | 91.65 | 99.60 | 94.88 | 98.76 | FAIL | text 2218 px |
| `components.model-retry.started-open-desktop-zh.dark` | dark | 91.40 | 99.25 | 92.67 | 98.82 | FAIL | text 2316 px |
| `components.model-retry.started-open-phone-en.light` | light | 93.05 | 99.32 | 94.41 | 96.87 | FAIL | text 4109 px |
| `components.model-retry.started-open-phone-en.dark` | dark | 92.96 | 99.05 | 93.67 | 96.91 | FAIL | text 4249 px |
| `components.model-retry.started-open-phone-zh.light` | light | 91.75 | 99.24 | 93.49 | 95.95 | FAIL | text 4523 px |
| `components.model-retry.started-open-phone-zh.dark` | dark | 91.63 | 98.89 | 92.63 | 95.93 | FAIL | text 4631 px |
| `components.model-retry.cancelled-open-desktop-en.light` | light | 92.12 | 99.71 | 95.65 | 98.83 | FAIL | text 2092 px |
| `components.model-retry.cancelled-open-desktop-en.dark` | dark | 91.97 | 99.44 | 93.20 | 98.76 | FAIL | text 2116 px |
| `components.model-retry.cancelled-open-desktop-zh.light` | light | 90.98 | 99.59 | 94.58 | 98.70 | FAIL | text 2407 px |
| `components.model-retry.cancelled-open-desktop-zh.dark` | dark | 90.70 | 99.22 | 92.10 | 98.77 | FAIL | text 2518 px |
| `components.model-retry.cancelled-open-phone-en.light` | light | 94.26 | 97.97 | 95.38 | 97.45 | FAIL | text 4492 px |
| `components.model-retry.cancelled-open-phone-en.dark` | dark | 93.75 | 97.32 | 94.38 | 97.01 | FAIL | text 4602 px |
| `components.model-retry.cancelled-open-phone-zh.light` | light | 91.13 | 99.19 | 92.93 | 95.72 | FAIL | text 4943 px |
| `components.model-retry.cancelled-open-phone-zh.dark` | dark | 91.00 | 98.82 | 92.08 | 95.67 | FAIL | text 5037 px |

## Per area

| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |
|---|---:|---:|---:|---:|---:|
| model-retry | 32 | 32 | 0 | 91.74 | 97.51 |
