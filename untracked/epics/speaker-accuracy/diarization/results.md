| hypothesis | DER real | DER real no overlap | DER synthetic both channels | DER synthetic system only | speaker-count error real / synthetic | me/them | bleed | x realtime |
|---|---|---|---|---|---|---|---|---|
| baseline-parakeet | 0.262 | 0.207 | 0.938 | 0.606 | 0.60 / 0.88 | 0.077 | 0.678 | 13 |
| baseline-diarizer-raw | 0.119 | 0.059 | 0.767 | 0.295 | 0.60 / 0.88 | 0.034 | 0.000 | 13 |
| diar-echo-gate-parakeet | 0.262 | 0.207 | 0.481 | 0.606 | 0.60 / 1.00 | 0.031 | 0.013 | 803 |
| diar-timeline-parakeet | 0.130 | 0.073 | 0.772 | 0.295 | 0.60 / 0.88 | 0.029 | 0.678 | - |
| diar-timeline-echo-gate-parakeet | 0.130 | 0.073 | 0.282 | 0.295 | 0.60 / 1.00 | 0.001 | 0.013 | 803 |
| diar-offline-t0.5 | 0.131 | 0.074 | 0.264 | 0.271 | 0.60 / 0.75 | 0.001 | 0.013 | 46 |
