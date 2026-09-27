---
type: Decision Record
title: First payment path
status: proposed
tags: [distribution, payments]
generated:
  by: agent
  at: 2026-09-27T00:00:00Z
---

# First payment path (research checked 2026-09-27)

**Proposed, conditional — not an eligibility approval or legal/tax advice.** The existing [$49 one-time price and distribution plan](development-directions.md) remain unchanged. Eleven $49 sales make $539 **gross customer receipts** before tax, fees and refunds; ten make only $490. Gross receipts are not payout or profit. No account was opened or tested.

| Route | Seller eligibility and payout | One-time Mac app, fees/tax/refunds, licensing | Time to first charge |
|---|---|---|---|
| [Paddle](https://www.paddle.com/help/start/intro-to-paddle/which-countries-are-supported-by-paddle) | Explicitly excludes suppliers **operating from Russia**; [Russian payout accounts unlikely to receive funds](https://www.paddle.com/help/legal/sanctions/impact-of-sanctions-on-russia-and-belarus). A foreign entity alone does not establish eligibility. Other-country business/identity and payout review required. | Merchant of record, [5% + $0.50 per checkout](https://www.paddle.com/pricing), tax/compliance included; refunds reduce realized receipts. Checkout supports one-time software; [Mac licensing article](https://www.paddle.com/help/start/intro-to-paddle/selling-a-mac-app-with-trials-and-licensing) is **Classic only**, not proof of current Billing SDK licensing. Delivery/license implementation remains to choose. | [Domain, business, identity review](https://www.paddle.com/help/start/account-verification) before live sales; duration **unknown**. |
| [Lemon Squeezy](https://docs.lemonsqueezy.com/help/getting-started/supported-countries) | Requires supported bank or PayPal payout country; Russia absent from bank list. PayPal availability **for Mikhail specifically unknown**; supported foreign account/entity must be genuine. Buyers in Russia excluded. | Merchant of record; [5% + $0.50](https://www.lemonsqueezy.com/pricing), [possible international/PayPal and payout surcharges](https://docs.lemonsqueezy.com/help/getting-started/fees), tax handled by platform; [refunds may be issued by platform within 60 days and disputes incur charges](https://docs.lemonsqueezy.com/help/payments/refunds-chargebacks). One-time download and [license keys/API/webhooks](https://docs.lemonsqueezy.com/help/licensing) available; app integration still needed. | [ID verification and store activation](https://docs.lemonsqueezy.com/help/getting-started/verify-your-identity) before sales; duration **unknown**. |
| [Stripe](https://stripe.com/global) | Russia not listed as a supported business country. A real eligible-country business and [bank payout](https://docs.stripe.com/payouts) are prerequisites; residence/ownership and sanctions review **unknown**. | [Checkout/Payment Links](https://docs.stripe.com/payment-links) can sell once; [local pricing](https://stripe.com/pricing) varies by merchant country and payment method. Ordinary Stripe is not merchant of record: seller owns tax registration/remittance and refunds; [Stripe Tax](https://stripe.com/tax/pricing) is an additional service. License issuance must be built or sourced. | Eligibility/onboarding **unknown**; first payout [typically 7–14 days after first live payment](https://docs.stripe.com/payouts), possibly longer. |
| [Mac App Store](https://developer.apple.com/help/account/membership/program-enrollment/) | Individual or organization enrollment and paid-app banking/tax agreements require Apple's acceptance; whether Mikhail's residence, legal entity and bank can enroll/receive payment **unknown**. | Paid one-time Mac app is native; store distributes purchases (not independent serial keys), handles customer payment/tax under its agreements, refunds can reverse proceeds. [Small Business Program 15% commission if eligible](https://developer.apple.com/app-store/small-business-program/); otherwise applicable commission/terms need confirmation. [Current sandbox audit](app-store-sandbox.md) identifies a downloaded-executable blocker and additional build work. | Enrollment underway per directions; sandbox changes plus [App Review](https://developer.apple.com/app-store/review/guidelines/) make timing **unknown**, not the fastest presumed route. |

## Recommendation and gates

If Mikhail already has a **lawfully operated supported-country seller and payout arrangement**, first ask that provider to confirm seller eligibility **including actual residence/operations and beneficial ownership**. Prefer Lemon Squeezy direct distribution for the first eleven $49 orders if it approves: hosted one-time checkout, merchant-of-record tax handling, downloadable app and license keys avoid the Store sandbox work. Paddle is a fallback only if its Russia-operations exclusion does not apply and it explicitly approves the full facts. Do not use a nominee, misstate residency or route payouts around sanctions. If operations are in Russia and no provider confirms eligibility, **no verified card route exists from this research**: do not promise $500 or build checkout yet. Seek qualified local legal/tax advice on lawful direct sales and settlement; crypto is **not established as a lawful shortcut** (buyer payment, conversion, tax, refunds and sanctions remain unresolved). A supported Stripe business is another conditional route, but tax and licensing add work. App Store is a longer parallel distribution path, not a payment-only fix. Confirm live terms and a successful legitimate payout before relying on any forecast.

## Mikhail-only facts and choices needed (answer in order)

1. What is your actual country of residence and country from which you operate/supply Beseda? Are either in Russia or another restricted jurisdiction?
2. Will you sell as an individual or an existing legal entity? If entity: incorporation and operating country, beneficial-owner residence and tax residence (no account numbers or identity documents here).
3. Which countries have payout bank accounts **in your own/entity name**, and is PayPal merchant receipt and withdrawal actually available to you there?
4. Is Apple Developer enrollment approved, and can the same legal seller accept its paid-app agreement, banking and tax setup? No credentials needed.
5. Are first buyers outside Russia, and do you choose direct notarized distribution with hosted checkout and license keys if eligibility is confirmed?
6. Do you want $500 measured as customer charges **before tax/refunds**, or $500 collected net of tax, fees and refunds? The eleven-sales calculation uses the former.

**Unknowns:** provider's decision on this seller, actual payout availability, onboarding/review duration, country-specific fee/tax treatment, refund exposure and licensing implementation. Recheck vendor terms at application time; this is a dated source review, not an account approval.
