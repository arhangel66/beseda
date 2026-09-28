---
type: Decision Record
title: StoreKit-free paid app package
status: proposed
tags: [distribution, macos, app-store, pricing]
sources:
  - id: apple-paid
    title: Apple, Sign the Paid Apps Agreement
    url: https://developer.apple.com/help/app-store-connect/manage-agreements/sign-the-paid-apps-agreement/
  - id: apple-price
    title: Apple, Set a price
    url: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/
  - id: apple-receipt
    title: Apple, Validating receipts on the device
    url: https://developer.apple.com/documentation/appstorereceipts/validating-receipts-on-the-device
  - id: apple-submit
    title: Apple, Submit an app for review
    url: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app-for-review/
---

# StoreKit-free paid app package

**Proposed package:** a $39.99 one-time *paid download* on the Mac App Store, not an in-app purchase or subscription. The owner sets the storefront price in App Store Connect; Apple handles purchase, installation and updates.[^price] Beseda needs no StoreKit purchase screen, bespoke license server or DRM. A paid download is not itself an in-app product: do not add a subscription, trial entitlement gate, serial key or purchase restoration UI. If a later feature actually needs in-app purchases or app-managed purchase-dependent access, revisit the design and receipt/transaction validation then. Apple's receipt-validation documentation describes how to validate a receipt **when the app uses one to make an access decision**; it does not require Beseda to implement receipt validation merely to sell an upfront paid download.[^receipt] Do not assert that MAS receipts have already been validated.

## Candidate gates (not a submission authorization)

| Gate | Evidence now / required next |
|---|---|
| Seller | **Apple/account action unverified:** owner confirms Paid Apps Agreement **Active**, tax and banking complete, and applicable Digital Services Act trader status in App Store Connect. Paid Apps must be active to sell paid apps.[^paid] |
| Identity | **Local blocker:** obtain matching `app.beseda.Beseda` macOS profile and Mac App Distribution certificate/private key for intended team; inspect signed bundle/profile. Local inspection found neither matching profile nor distribution identity ([sandbox audit](app-store-sandbox.md#provisioned-signing-prerequisites-local-read-only-inspection)). |
| Package | **Static gate only:** build `BESEDA_STORE=1` artifact with pinned b10819 archive digest verified; bundle signed `llama-server` helper and dylibs, download **models only** at runtime, no executable download; no Sparkle framework/feed/UI. Check final provisioned candidate again. BESEDA-307 ad-hoc artifact passed these static checks, not runtime ([build evidence](../architecture/build-release.md#private-store-artifact-beseda-257)). |
| Listing | **Unverified Apple action:** owner prepares English metadata, working privacy and support URLs, and accurate screenshots of the actual candidate; verifies disclosures and storefront price/availability before review. No listing or public price was changed here. |
| Runtime | **Unverified:** on a disposable account with intended provisioned identity, test sandbox helper/model load, bookmark export/relaunch, Keychain, and microphone **and system-audio process tap** grant and nonzero isolated capture across relaunch. Follow the [owner-supervised capture criterion](app-store-sandbox.md#owner-supervised-sandbox-capture-experiment-not-run); ad-hoc signature and entitlements do not prove this. |
| Independent review | **Not obtained for this candidate:** independent GPT-6 Astra verdict on exact artifact, evidence and remaining risks before owner decision. The older source-only [distribution verdict](distribution-readiness.md) predates the Store split and is not candidate approval. |
| Release | **Owner/Apple action unverified:** owner explicitly approves before submission **and** publication; only then submit for App Review.[^submit] After release, keep a charge ledger of actual paid, non-refunded orders and gross charges (separate from Apple proceeds), using the [first-sale price definition](first-sale-price.md#first-500). |

No account login, app launch, upload, public price setting or publication is evidence of this document. Existing static checks do not close provisioned sandbox, Apple account, App Review or live-sales gates.

[^paid]: [Apple Paid Apps Agreement](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-the-paid-apps-agreement/).
[^price]: [Apple price setup](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/) and [App Store distribution](https://developer.apple.com/app-store/).
[^receipt]: [Apple on-device receipt validation](https://developer.apple.com/documentation/appstorereceipts/validating-receipts-on-the-device); this is conditional guidance, not evidence of a requirement for an ungated paid app.
[^submit]: [Apple submission steps](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app-for-review/).
