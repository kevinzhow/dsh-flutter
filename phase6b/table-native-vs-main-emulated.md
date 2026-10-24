| group | n | exact % before | after | non-text % before | after | pass before | after |
|---|---:|---:|---:|---:|---:|---:|---:|
| core: button | 17 | 95.02 | 95.50 | 98.01 | 98.44 | 3 | 3 |
| ext: attachment | 36 | 97.64 | 97.65 | 98.68 | 98.70 | 33 | 33 |
| ext: button | 32 | 94.03 | 94.58 | 98.20 | 98.46 | 0 | 0 |
| ext: code | 30 | 96.21 | 96.25 | 98.35 | 98.36 | 22 | 22 |
| ext: connection-indicator | 12 | 97.16 | 97.28 | 98.17 | 98.28 | 12 | 12 |
| ext: plan | 8 | 86.40 | 92.69 | 89.03 | 95.01 | 1 | 1 |
| ext: question-wait | 16 | 82.43 | 85.21 | 91.89 | 93.31 | 0 | 0 |
| ext: settings | 60 | 98.07 | 98.14 | 98.97 | 99.06 | 60 | 60 |
| ext: terminal | 36 | 99.69 | 99.69 | 99.87 | 99.88 | 36 | 36 |
| ext: tool | 4 | 96.45 | 96.23 | 98.28 | 98.37 | 3 | 2 |
| **all** | 251 | **95.86** | **96.37** | **98.00** | **98.38** | **170** | **169** |

Cases whose exact % dropped by more than 0.3 points (2 of 251):
- `components.tool.bash.row.states.dark` 96.27 -> 95.74 (-0.53)
- `components.tool.bash.row.states.light` 95.94 -> 95.62 (-0.31)

Captures only in the after run (14):
- `components.button.variants.md-2p625x.light` 98.16 exact, 98.96 non-text, basic-pass
- `components.button.variants.md-3x.light` 98.34 exact, 99.21 non-text, basic-pass
- `components.connection-indicator.states-2p625x.dark` 98.13 exact, 98.81 non-text, basic-pass
- `components.connection-indicator.states-2p625x.dark~hover` 98.13 exact, 98.82 non-text, basic-pass
- `components.connection-indicator.states-2p625x.dark~press` 98.13 exact, 98.81 non-text, basic-pass
- `components.connection-indicator.states-2p625x.light` 98.15 exact, 98.84 non-text, basic-pass
- `components.connection-indicator.states-2p625x.light~hover` 98.15 exact, 98.84 non-text, basic-pass
- `components.connection-indicator.states-2p625x.light~press` 98.15 exact, 98.84 non-text, basic-pass
- `components.connection-indicator.states-3x.dark` 98.13 exact, 98.87 non-text, basic-pass
- `components.connection-indicator.states-3x.dark~hover` 98.13 exact, 98.86 non-text, basic-pass
- `components.connection-indicator.states-3x.dark~press` 98.13 exact, 98.86 non-text, basic-pass
- `components.connection-indicator.states-3x.light` 98.16 exact, 98.91 non-text, basic-pass
- `components.connection-indicator.states-3x.light~hover` 98.16 exact, 98.91 non-text, basic-pass
- `components.connection-indicator.states-3x.light~press` 98.16 exact, 98.91 non-text, basic-pass
