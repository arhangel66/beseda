# Decisions

- [App Review recording policy preflight](app-review-policy.md) — preliminary source-only recording consent and disclosure audit.

- [Failed native macOS design research](native-macos-design.md) — neither offscreen SwiftUI direction passed the design gate; no candidate was selected.

- [Sales UX screen audit and design proposals](design-review-sales.md) — source-bounded screen review and three static concepts; proposed.

- [English first buyers](english-first-buyers.md) — localized source and bundle audit; visual gate parked.
- [First-sale price](first-sale-price.md) — approved $39.99 one-time Mac App Store launch price, evidence and gross-order threshold.
- [StoreKit-free paid app package](paid-app-package.md) — upfront Store distribution and candidate gates; proposed.
- [Distribution readiness](distribution-readiness.md) — source-only private notarization, Mac App Store and public release verdicts; proposed.
- [Trial and access](trial-access.md) — proposed provider-neutral evaluation and archive-safe entitlement boundary.
- [First payment path](payment-path.md) — conditional comparison of seller eligibility and first $500 gross receipts; proposed.
- [App Store sandbox audit](app-store-sandbox.md) — direct/Store split, private full-bundle static evidence and parked runtime/Apple gates; proposed.
- [Pre-handoff UX review, round 2](ux-review-2.md) — first-time-user and psychologist findings across the current native UI; proposed.
- [Adversarial product and code review](critic-review.md) — product, architecture, speaker, privacy and release findings; proposed.
- [Development directions](development-directions.md) — where Beseda goes next: Mikhail's answers and the phased plan; approved with changes.
- [Speaker accuracy, local](speaker-accuracy.md) — echo gate, diarizer timeline, Nemotron-3 as the diarizer without the 6 s rule.
- [Local on-device ASR](local-asr.md) — speech is transcribed on the Mac, no cloud ASR.
- [Separate microphone and system channels](separate-channels.md) — "me" and "them" recorded to separate files.
- [ASR engine](asr-engine.md) — transcribe.cpp with a user-picked Parakeet or GigaAM model, replacing parakeet-mlx.
- [Summarization runtime](summarization-runtime.md) — built-in llama-server by default, OpenRouter or LM Studio by choice.
- [Native SwiftUI menu-bar app](native-menubar-app.md) — one SwiftPM target, `MenuBarExtra`, system controls.
- [SQLite call index](sqlite-storage.md) — `calls.sqlite` through the system SQLite3 API.
- [Call-type classifier](call-type-classifier.md) — Jev via OpenRouter by default when a key is set, the summary model otherwise; accepted.
- [Refactor for quality and load](refactor-for-quality-and-load.md) — which incidental decisions to refactor; proposed.
- [Ponytail cleanup (BESEDA-4)](ponytail-cleanup.md) — what the cleanup removed; no behaviour changed.
- [At-rest encryption](at-rest-encryption.md) — threat model and options beyond FileVault; recommends FileVault warning, backup exclusion and «Строгий режим», no SQLCipher; proposed.
