# Google Play Billing setup

Prices are **never hardcoded**: the Pro screen shows exactly what Google Play returns for each product. The proposed
launch prices (₹49 / month, ₹399 / year) are configured in Play Console, not in code.

## 1. Play Console (requires your developer account — nothing here is done automatically)

1. Create the app with the final application id (default `in.creovix.spendwise`).
2. Upload a signed AAB to an *internal testing* track (billing only works for Play-installed builds).
3. Monetize → Subscriptions → create two subscriptions with product ids matching your build defines
   (defaults `spendwise_pro_monthly`, `spendwise_pro_annual`). Add a base plan each (monthly auto-renewing ₹49;
   yearly auto-renewing ₹399), set grace period/account hold as you prefer, **activate** them.
4. Setup → License testing: add tester Gmail accounts (these purchase for free / with accelerated renewals).
5. Complete the merchant profile / payments profile, tax and Data-safety/Financial-features forms.

## 2. App configuration

`--dart-define=SPENDWISE_MONTHLY_ID=...` and `--dart-define=SPENDWISE_ANNUAL_ID=...` (defaults already match the ids above).
Billing library is provided by `in_app_purchase_android` (Play Billing Library 9.x, `minSdk 24`).

## 3. What the client already implements

`lib/services/billing/`: availability check, product query, purchase initiation, purchase stream (pending / purchased /
restored / canceled / error), acknowledgement via `completePurchase` (only after the entitlement decision succeeds),
restore purchases, entitlement re-evaluation on every start, subscription-management deep link
(`https://play.google.com/store/account/subscriptions?package=...`), graceful behaviour when billing is unavailable.
Refunds, cancellations and expiry: Play stops returning the purchase, so the grant lapses (≤72 h without a backend,
immediately at server-reported expiry with one).

## 4. Server-side verification (recommended before relying on Pro for anything valuable)

Not included in this repository. Contract the client expects when `SPENDWISE_VERIFY_URL` (HTTPS) is set:

```
POST {SPENDWISE_VERIFY_URL}/v1/subscriptions/verify
{"packageName":"in.creovix.spendwise","productId":"spendwise_pro_monthly","purchaseToken":"..."}
→ 200 {"active": true, "expiryTimeMillis": 1767225600000}
```

Backend duties: call the Google Play Developer API (`purchases.subscriptionsv2.get`) with a **service account kept only on
the server**; check `packageName` matches and the product id is one of yours; check `subscriptionState`
(`ACTIVE`/`IN_GRACE_PERIOD` = active) and the line item `expiryTime`; treat repeated calls idempotently; optionally
acknowledge server-side; subscribe to Real-time Developer Notifications (Pub/Sub) to learn about renewals, cancellations,
refunds and revocations and update stored state. Never ship the service-account JSON in the APK/AAB or in git.

While a verifier is configured the client will **not** grant Pro without a successful verification, and will not
acknowledge the purchase if verification could not be completed (Play re-delivers it on the next launch; remember
unacknowledged purchases are refunded after 3 days, so keep the backend reliable).

## 5. Test scenarios (do these on a Play-installed internal-test build with a license tester)

Buy monthly · buy yearly · cancel in the Play sheet · slow/declined test card (pending) · restore on a second device ·
cancel subscription then wait for expiry (accelerated in test) · airplane mode during launch · uninstall/reinstall + Restore.
Expected: free features never lock; Pro status matches Play within the documented windows.

**Status of this verification:** not performed — it needs your Play Console setup. Unit tests cover the entitlement
rules and the purchase-event handling with fakes (`test/unit/entitlement_test.dart`).
