import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spendwise/services/billing/billing_config.dart';

class VerificationResult {
  const VerificationResult({required this.active, this.expiresAt});
  final bool active;
  final DateTime? expiresAt;
}

/// Server-side verification of Google Play purchase tokens.
abstract class PurchaseVerifier {
  bool get isConfigured;

  /// Returns null when verification could not be completed (offline, server
  /// error). Callers must NOT grant verified access in that case.
  Future<VerificationResult?> verify({
    required String productId,
    required String purchaseToken,
  });
}

/// Used until a backend exists. Never reports success.
class UnconfiguredPurchaseVerifier implements PurchaseVerifier {
  const UnconfiguredPurchaseVerifier();
  @override
  bool get isConfigured => false;
  @override
  Future<VerificationResult?> verify({
    required String productId,
    required String purchaseToken,
  }) async => null;
}

/// Talks to your own backend, which must call the Google Play Developer API
/// (purchases.subscriptionsv2.get) with a service account kept server-side.
///
/// Contract:  POST {SPENDWISE_VERIFY_URL}/v1/subscriptions/verify
///   body:    {"packageName": "...", "productId": "...", "purchaseToken": "..."}
///   200 OK:  {"active": true, "expiryTimeMillis": 1767225600000}
class HttpPurchaseVerifier implements PurchaseVerifier {
  HttpPurchaseVerifier(this.baseUrl);
  final String baseUrl;

  @override
  bool get isConfigured => baseUrl.startsWith('https://');

  @override
  Future<VerificationResult?> verify({
    required String productId,
    required String purchaseToken,
  }) async {
    if (!isConfigured) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/subscriptions/verify',
      );
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 15));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'packageName': BillingConfig.packageName,
          'productId': productId,
          'purchaseToken': purchaseToken,
        }),
      );
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final active = json['active'] == true;
      final expiry = json['expiryTimeMillis'];
      return VerificationResult(
        active: active,
        expiresAt: expiry is int
            ? DateTime.fromMillisecondsSinceEpoch(expiry)
            : null,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
