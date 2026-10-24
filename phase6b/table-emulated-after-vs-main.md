| group | n | exact % before | after | non-text % before | after | pass before | after |
|---|---:|---:|---:|---:|---:|---:|---:|
| core: button | 17 | 95.02 | 95.51 | 98.01 | 98.44 | 3 | 3 |
| ext: attachment | 36 | 97.64 | 97.64 | 98.68 | 98.68 | 33 | 33 |
| ext: button | 32 | 94.03 | 94.58 | 98.20 | 98.46 | 0 | 0 |
| ext: code | 30 | 96.21 | 96.21 | 98.35 | 98.35 | 22 | 22 |
| ext: connection-indicator | 12 | 97.16 | 97.25 | 98.17 | 98.26 | 12 | 12 |
| ext: plan | 8 | 86.40 | 86.41 | 89.03 | 89.03 | 1 | 1 |
| ext: question-wait | 16 | 82.43 | 82.52 | 91.89 | 91.97 | 0 | 0 |
| ext: settings | 60 | 98.07 | 98.14 | 98.97 | 99.05 | 60 | 60 |
| ext: terminal | 36 | 99.69 | 99.69 | 99.87 | 99.88 | 36 | 36 |
| ext: tool | 4 | 96.45 | 96.48 | 98.28 | 98.31 | 3 | 3 |
| **all** | 251 | **95.86** | **95.99** | **98.00** | **98.09** | **170** | **170** |

Cases whose exact % dropped by more than 0.2 points (2 of 251):
- `components.question-wait.paused-zh.light` 83.29 -> 82.96 (-0.33)
- `components.question-wait.paused-zh.dark` 81.27 -> 81.00 (-0.28)

Captures only in the after run (14):
- `components.button.variants.md-2p625x.light` 97.84 exact, 98.67 non-text, fail
- `components.button.variants.md-3x.light` 98.37 exact, 99.25 non-text, basic-pass
- `components.connection-indicator.states-2p625x.dark` 97.72 exact, 98.38 non-text, basic-pass
- `components.connection-indicator.states-2p625x.dark~hover` 97.65 exact, 98.32 non-text, basic-pass
- `components.connection-indicator.states-2p625x.dark~press` 97.63 exact, 98.30 non-text, basic-pass
- `components.connection-indicator.states-2p625x.light` 97.76 exact, 98.43 non-text, basic-pass
- `components.connection-indicator.states-2p625x.light~hover` 97.76 exact, 98.43 non-text, basic-pass
- `components.connection-indicator.states-2p625x.light~press` 97.67 exact, 98.35 non-text, basic-pass
- `components.connection-indicator.states-3x.dark` 98.10 exact, 98.84 non-text, basic-pass
- `components.connection-indicator.states-3x.dark~hover` 98.09 exact, 98.84 non-text, basic-pass
- `components.connection-indicator.states-3x.dark~press` 98.10 exact, 98.84 non-text, basic-pass
- `components.connection-indicator.states-3x.light` 98.12 exact, 98.86 non-text, basic-pass
- `components.connection-indicator.states-3x.light~hover` 98.12 exact, 98.86 non-text, basic-pass
- `components.connection-indicator.states-3x.light~press` 98.12 exact, 98.86 non-text, basic-pass
