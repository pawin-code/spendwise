/// Subscription entitlement rules. Pure Dart so they can be unit tested.
///
/// Entitlements live outside the transaction database and are never inferred
/// from a bare local flag: they come from a purchase that Google Play reported
/// recently and, when a backend is configured, that the backend verified.
library;

enum EntitlementSource { none, googlePlay, serverVerified }

enum PlayPurchaseState { pending, purchased }

/// What the device last learned about a subscription purchase.
class PurchaseRecord {
  const PurchaseRecord({
    required this.productId,
    required this.state,
    required this.lastConfirmedByPlay,
    this.serverVerifiedUntil,
  });

  final String productId;
  final PlayPurchaseState state;

  /// Last time Google Play itself reported this purchase as owned.
  final DateTime lastConfirmedByPlay;

  /// Expiry returned by the verification backend, if one verified the token.
  final DateTime? serverVerifiedUntil;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'state': state.name,
    'lastConfirmedByPlay': lastConfirmedByPlay.millisecondsSinceEpoch,
    'serverVerifiedUntil': serverVerifiedUntil?.millisecondsSinceEpoch,
  };

  static PurchaseRecord? fromJson(Map<String, dynamic> j) {
    try {
      return PurchaseRecord(
        productId: j['productId'] as String,
        state: PlayPurchaseState.values.byName(j['state'] as String),
        lastConfirmedByPlay: DateTime.fromMillisecondsSinceEpoch(
          j['lastConfirmedByPlay'] as int,
        ),
        serverVerifiedUntil: j['serverVerifiedUntil'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                j['serverVerifiedUntil'] as int,
              ),
      );
    } catch (_) {
      return null;
    }
  }
}

class Entitlement {
  const Entitlement({
    required this.isPro,
    required this.source,
    this.productId,
    this.expiresAt,
    this.pending = false,
    this.message = '',
  });

  static const free = Entitlement(isPro: false, source: EntitlementSource.none);

  final bool isPro;
  final EntitlementSource source;
  final String? productId;
  final DateTime? expiresAt;
  final bool pending;
  final String message;
}

/// How long a Google Play confirmation is trusted without server verification.
/// Expired/cancelled/refunded subscriptions stop being reported by Play, so
/// the grant lapses within this window unless Play confirms it again.
const Duration kUnverifiedGrace = Duration(hours: 72);

Entitlement evaluateEntitlement(
  PurchaseRecord? record,
  DateTime now, {
  required bool verifierConfigured,
}) {
  if (record == null) return Entitlement.free;
  if (record.state == PlayPurchaseState.pending) {
    return const Entitlement(
      isPro: false,
      source: EntitlementSource.none,
      pending: true,
      message: 'Your purchase is pending. Pro unlocks once Google Play confirms the payment.',
    );
  }
  final verifiedUntil = record.serverVerifiedUntil;
  if (verifiedUntil != null) {
    if (now.isBefore(verifiedUntil)) {
      return Entitlement(
        isPro: true,
        source: EntitlementSource.serverVerified,
        productId: record.productId,
        expiresAt: verifiedUntil,
      );
    }
    return const Entitlement(
      isPro: false,
      source: EntitlementSource.none,
      message: 'Your Pro subscription has expired.',
    );
  }
  if (verifierConfigured) {
    return const Entitlement(
      isPro: false,
      source: EntitlementSource.none,
      message: 'Waiting for purchase verification. Check your connection and tap Restore purchases.',
    );
  }
  final grantEnds = record.lastConfirmedByPlay.add(kUnverifiedGrace);
  if (now.isBefore(grantEnds)) {
    return Entitlement(
      isPro: true,
      source: EntitlementSource.googlePlay,
      productId: record.productId,
      expiresAt: grantEnds,
      message: 'Confirmed by Google Play on this device.',
    );
  }
  return const Entitlement(
    isPro: false,
    source: EntitlementSource.none,
    message: 'Pro could not be re-confirmed with Google Play. Tap Restore purchases.',
  );
}
