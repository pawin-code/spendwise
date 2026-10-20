/// Billing configuration. Product ids and the verification endpoint come from
/// build-time defines, never from source-controlled secrets:
///
///   flutter build appbundle --release \
///     --dart-define=SPENDWISE_MONTHLY_ID=spendwise_pro_monthly \
///     --dart-define=SPENDWISE_ANNUAL_ID=spendwise_pro_annual \
///     --dart-define=SPENDWISE_VERIFY_URL=https://api.example.com
///
/// Prices are NEVER hardcoded: the UI shows what Google Play returns.
class BillingConfig {
  const BillingConfig._();

  static const String packageName = String.fromEnvironment(
    'SPENDWISE_PACKAGE',
    defaultValue: 'in.creovix.spendwise',
  );
  static const String monthlyProductId = String.fromEnvironment(
    'SPENDWISE_MONTHLY_ID',
    defaultValue: 'spendwise_pro_monthly',
  );
  static const String annualProductId = String.fromEnvironment(
    'SPENDWISE_ANNUAL_ID',
    defaultValue: 'spendwise_pro_annual',
  );

  /// Base URL of your purchase-verification backend (HTTPS only). Empty = not configured.
  static const String verifyUrl = String.fromEnvironment(
    'SPENDWISE_VERIFY_URL',
  );

  static const Set<String> productIds = {monthlyProductId, annualProductId};

  static bool get verifierConfigured => verifyUrl.startsWith('https://');
}
