/// In-app copies of the policies. Publish the same text at a public URL and
/// link it in Play Console before release (see docs/PLAY_STORE_RELEASE.md).
/// REPLACE the bracketed placeholders before publishing.
const String kPrivacyPolicyText = '''
SpendWise Privacy Policy
Last updated: [DATE — replace before release]

SpendWise is a personal finance tracker that keeps your data on your device.

1. What we collect
SpendWise does not collect, transmit or sell the transactions, budgets, wallets, categories, notes or amounts you enter. They are stored only in the app's private storage on your device.

SpendWise does not ask for, read or store bank logins, card numbers, PINs, passwords or one-time passwords, and it does not read your SMS, contacts, call history or location.

2. Purchases
If you choose to buy SpendWise Pro, the purchase is handled by Google Play. Google processes your payment and shares purchase status (such as a purchase token and product id) with the app so Pro can be unlocked. If a verification service is configured, the purchase token and product id are sent over HTTPS to that service to confirm the subscription; no financial records are sent.

3. Crash and analytics data
This version does not include analytics or third-party crash reporting. If that changes, this policy will be updated before release and will never include transaction details.

4. Notifications
Bill reminders and budget alerts are generated on your device. Reminder text never includes amounts. You can turn notifications off at any time.

5. Exports and backups
When you export a CSV or create a backup, the file is created only after you choose where to save or share it. Those files are not encrypted; you are responsible for where you store or send them.

6. Deleting your data
Use Settings > Privacy & data > Erase all data to delete every record from the app. Uninstalling the app also removes its private storage. Files you exported or backed up yourself are not removed automatically.

7. Children
SpendWise is not directed at children under 13.

8. Contact
[SUPPORT EMAIL — replace before release]
''';

const String kTermsText = '''
SpendWise Terms of Service
Last updated: [DATE — replace before release]

1. The app
SpendWise helps you record and review your own income and spending. It is a bookkeeping tool, not financial, tax or investment advice. Figures such as Safe-to-Spend are estimates based only on what you enter.

2. Your data
You own your data. SpendWise stores it on your device. You are responsible for keeping backups you care about.

3. SpendWise Pro
Pro is an optional auto-renewing subscription sold through Google Play. Your subscription renews automatically until you cancel it in Google Play (Play Store > Profile > Payments & subscriptions > Subscriptions). Cancelling stops future renewals; you keep Pro until the end of the paid period. Prices are shown in your local currency by Google Play before you confirm. Refunds are handled by Google Play according to its policies.

4. Free features
Core tracking, budgets, reminders, reports and CSV export remain free and are not limited by the number of transactions.

5. No warranty
The app is provided "as is". To the extent permitted by law, we are not liable for losses arising from reliance on the app's calculations or from lost data.

6. Changes
We may update these terms; continued use means you accept the updated terms.

7. Contact
[SUPPORT EMAIL — replace before release]
''';
