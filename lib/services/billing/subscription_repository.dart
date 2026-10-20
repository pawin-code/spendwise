import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/services/billing/billing_config.dart';
import 'package:spendwise/services/billing/billing_gateway.dart';
import 'package:spendwise/services/billing/entitlement.dart';
import 'package:spendwise/services/billing/purchase_verifier.dart';

enum BillingPhase { idle, loading, ready, unavailable, purchasing, restoring }

class BillingState {
  const BillingState({
    this.phase = BillingPhase.idle,
    this.products = const [],
    this.entitlement = Entitlement.free,
    this.message,
  });

  final BillingPhase phase;
  final List<BillingProduct> products;
  final Entitlement entitlement;

  /// Latest user-facing status or error (null when there is nothing to show).
  final String? message;

  BillingState copyWith({
    BillingPhase? phase,
    List<BillingProduct>? products,
    Entitlement? entitlement,
    Object? message = _keep,
  }) => BillingState(
    phase: phase ?? this.phase,
    products: products ?? this.products,
    entitlement: entitlement ?? this.entitlement,
    message: identical(message, _keep) ? this.message : message as String?,
  );

  static const Object _keep = Object();
}

/// Owns purchase handling and entitlement refresh. Keeps no financial data.
class SubscriptionRepository {
  SubscriptionRepository({
    required this._gateway,
    required this._verifier,
    required this._prefs,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _kRecord = 'billing_record_v1';

  final BillingGateway _gateway;
  final PurchaseVerifier _verifier;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  final _state = StreamController<BillingState>.broadcast();
  BillingState _current = const BillingState();
  StreamSubscription<BillingEvent>? _sub;

  BillingState get current => _current;
  Stream<BillingState> get stream => _state.stream;

  void _emit(BillingState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  PurchaseRecord? _readRecord() {
    final raw = _prefs.getString(_kRecord);
    if (raw == null) return null;
    try {
      return PurchaseRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRecord(PurchaseRecord? r) async {
    if (r == null) {
      await _prefs.remove(_kRecord);
    } else {
      await _prefs.setString(_kRecord, jsonEncode(r.toJson()));
    }
  }

  Entitlement _evaluate() => evaluateEntitlement(
    _readRecord(),
    _clock(),
    verifierConfigured: _verifier.isConfigured,
  );

  /// Loads the cached entitlement, starts listening to purchases and asks Play
  /// to re-deliver owned purchases. Never throws: free features must keep working.
  Future<void> start() async {
    _emit(
      _current.copyWith(entitlement: _evaluate(), phase: BillingPhase.loading),
    );
    try {
      final available = await _gateway.isAvailable();
      if (!available) {
        _emit(
          _current.copyWith(
            phase: BillingPhase.unavailable,
            entitlement: _evaluate(),
            message: 'Google Play Billing is not available on this device. All free features still work.',
          ),
        );
        return;
      }
      _sub ??= _gateway.events.listen(_onEvent);
      await refreshProducts();
      await _gateway.restore();
    } catch (_) {
      _emit(
        _current.copyWith(
          phase: BillingPhase.unavailable,
          entitlement: _evaluate(),
        ),
      );
    }
  }

  Future<void> refreshProducts() async {
    final r = await _gateway.loadProducts(BillingConfig.productIds);
    final ordered = [...r.products]
      ..sort(
        (a, b) => (a.id == BillingConfig.monthlyProductId ? 0 : 1).compareTo(
          b.id == BillingConfig.monthlyProductId ? 0 : 1,
        ),
      );
    _emit(
      _current.copyWith(
        phase: BillingPhase.ready,
        products: ordered,
        message: r.error,
        entitlement: _evaluate(),
      ),
    );
  }

  Future<void> buy(BillingProduct product) async {
    _emit(_current.copyWith(phase: BillingPhase.purchasing, message: null));
    try {
      final started = await _gateway.buy(product);
      if (!started) {
        _emit(
          _current.copyWith(
            phase: BillingPhase.ready,
            message: 'Could not start the purchase. Please try again.',
          ),
        );
      }
    } catch (_) {
      _emit(
        _current.copyWith(
          phase: BillingPhase.ready,
          message: 'Could not start the purchase. Please try again.',
        ),
      );
    }
  }

  Future<void> restore() async {
    _emit(_current.copyWith(phase: BillingPhase.restoring, message: null));
    try {
      await _gateway.restore();
      _emit(
        _current.copyWith(
          phase: BillingPhase.ready,
          entitlement: _evaluate(),
          message: 'Checked Google Play for purchases.',
        ),
      );
    } catch (_) {
      _emit(
        _current.copyWith(
          phase: BillingPhase.ready,
          message: 'Could not reach Google Play. Check your connection.',
        ),
      );
    }
  }

  Future<void> _onEvent(BillingEvent e) async {
    switch (e.status) {
      case BillingEventStatus.pending:
        await _writeRecord(
          PurchaseRecord(
            productId: e.productId,
            state: PlayPurchaseState.pending,
            lastConfirmedByPlay: _clock(),
          ),
        );
        _emit(
          _current.copyWith(
            phase: BillingPhase.ready,
            entitlement: _evaluate(),
          ),
        );
      case BillingEventStatus.canceled:
        _emit(
          _current.copyWith(
            phase: BillingPhase.ready,
            message: 'Purchase canceled. You have not been charged.',
          ),
        );
      case BillingEventStatus.error:
        _emit(
          _current.copyWith(
            phase: BillingPhase.ready,
            message: e.errorMessage ?? 'The purchase failed. Please try again.',
          ),
        );
        await _gateway.complete(e);
      case BillingEventStatus.purchased:
      case BillingEventStatus.restored:
        await _handlePurchased(e);
    }
  }

  Future<void> _handlePurchased(BillingEvent e) async {
    if (!BillingConfig.productIds.contains(e.productId)) {
      // Not one of our subscriptions; ignore but let the plugin finish it.
      await _gateway.complete(e);
      return;
    }
    final now = _clock();
    DateTime? serverUntil;
    var canAcknowledge = true;
    if (_verifier.isConfigured) {
      final result = await _verifier.verify(
        productId: e.productId,
        purchaseToken: e.purchaseToken ?? '',
      );
      if (result == null) {
        // Could not verify (offline / server error). Do not grant, and do not
        // acknowledge, so Play re-delivers the purchase next launch.
        canAcknowledge = false;
      } else if (result.active) {
        serverUntil = result.expiresAt ?? now.add(const Duration(days: 1));
      } else {
        await _writeRecord(null);
        _emit(
          _current.copyWith(
            phase: BillingPhase.ready,
            entitlement: Entitlement.free,
            message: 'This subscription is no longer active.',
          ),
        );
        await _gateway.complete(e);
        return;
      }
    }
    if (canAcknowledge || serverUntil != null) {
      await _writeRecord(
        PurchaseRecord(
          productId: e.productId,
          state: PlayPurchaseState.purchased,
          lastConfirmedByPlay: now,
          serverVerifiedUntil: serverUntil,
        ),
      );
    }
    if (canAcknowledge) await _gateway.complete(e);
    final ent = _evaluate();
    _emit(
      _current.copyWith(
        phase: BillingPhase.ready,
        entitlement: ent,
        message: ent.isPro
            ? 'SpendWise Pro is active. Thank you!'
            : ent.message,
      ),
    );
  }

  Future<void> clearLocalEntitlement() async {
    await _writeRecord(null);
    _emit(_current.copyWith(entitlement: Entitlement.free));
  }

  Uri manageSubscriptionUri() => Uri.https(
    'play.google.com',
    '/store/account/subscriptions',
    {'package': BillingConfig.packageName},
  );

  void dispose() {
    _sub?.cancel();
    _gateway.dispose();
    _state.close();
  }
}
