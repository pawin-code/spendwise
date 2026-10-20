import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/services/billing/billing_config.dart';
import 'package:spendwise/services/billing/billing_gateway.dart';
import 'package:spendwise/services/billing/entitlement.dart';
import 'package:spendwise/services/billing/purchase_verifier.dart';
import 'package:spendwise/services/billing/subscription_repository.dart';

final t0 = DateTime(2026, 10, 20, 12);

PurchaseRecord rec({
  PlayPurchaseState state = PlayPurchaseState.purchased,
  DateTime? confirmed,
  DateTime? serverUntil,
}) => PurchaseRecord(
  productId: BillingConfig.monthlyProductId,
  state: state,
  lastConfirmedByPlay: confirmed ?? t0,
  serverVerifiedUntil: serverUntil,
);

class FakeGateway implements BillingGateway {
  final controller = StreamController<BillingEvent>.broadcast();
  final completed = <BillingEvent>[];
  bool available = true;
  int restoreCalls = 0;

  @override
  Stream<BillingEvent> get events => controller.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<BillingProductsResult> loadProducts(Set<String> ids) async =>
      BillingProductsResult(
        products: [
          for (final id in ids)
            BillingProduct(
              id: id,
              title: id,
              description: '',
              priceText: id == BillingConfig.annualProductId
                  ? '₹399.00'
                  : '₹49.00',
              handle: id,
            ),
        ],
      );
  @override
  Future<bool> buy(BillingProduct product) async => true;
  @override
  Future<void> restore() async => restoreCalls++;
  @override
  Future<void> complete(BillingEvent event) async => completed.add(event);
  @override
  void dispose() => controller.close();
}

class FakeVerifier implements PurchaseVerifier {
  FakeVerifier({this.configured = true, this.result});
  final bool configured;
  VerificationResult? result;
  int calls = 0;
  @override
  bool get isConfigured => configured;
  @override
  Future<VerificationResult?> verify({
    required String productId,
    required String purchaseToken,
  }) async {
    calls++;
    return result;
  }
}

void main() {
  group('evaluateEntitlement', () {
    test('no record means free', () {
      final e = evaluateEntitlement(null, t0, verifierConfigured: false);
      expect(e.isPro, isFalse);
      expect(e.source, EntitlementSource.none);
    });

    test('pending purchases never unlock Pro', () {
      final e = evaluateEntitlement(
        rec(state: PlayPurchaseState.pending),
        t0,
        verifierConfigured: false,
      );
      expect(e.isPro, isFalse);
      expect(e.pending, isTrue);
    });

    test(
      'server-verified purchases are Pro until the server expiry, then free',
      () {
        final until = t0.add(const Duration(days: 30));
        expect(
          evaluateEntitlement(
            rec(serverUntil: until),
            t0,
            verifierConfigured: true,
          ).isPro,
          isTrue,
        );
        expect(
          evaluateEntitlement(
            rec(serverUntil: until),
            t0,
            verifierConfigured: true,
          ).source,
          EntitlementSource.serverVerified,
        );
        expect(
          evaluateEntitlement(
            rec(serverUntil: until),
            until,
            verifierConfigured: true,
          ).isPro,
          isFalse,
        );
        expect(
          evaluateEntitlement(
            rec(serverUntil: until),
            until.add(const Duration(days: 1)),
            verifierConfigured: true,
          ).message,
          contains('expired'),
        );
      },
    );

    test(
      'when a verifier is configured an unverified purchase is NOT granted',
      () {
        final e = evaluateEntitlement(rec(), t0, verifierConfigured: true);
        expect(e.isPro, isFalse);
        expect(e.message, contains('verification'));
      },
    );

    test('without a backend, Play confirmation is trusted only for the grace window', () {
      expect(
        evaluateEntitlement(
          rec(),
          t0.add(const Duration(hours: 71)),
          verifierConfigured: false,
        ).isPro,
        isTrue,
      );
      expect(
        evaluateEntitlement(
          rec(),
          t0.add(const Duration(hours: 71)),
          verifierConfigured: false,
        ).source,
        EntitlementSource.googlePlay,
      );
      expect(
        evaluateEntitlement(
          rec(),
          t0.add(kUnverifiedGrace),
          verifierConfigured: false,
        ).isPro,
        isFalse,
      );
      expect(
        evaluateEntitlement(
          rec(),
          t0.add(const Duration(days: 40)),
          verifierConfigured: false,
        ).isPro,
        isFalse,
      );
    });

    test('records survive a JSON round trip and corrupt JSON is rejected', () {
      final r = rec(serverUntil: t0.add(const Duration(days: 1)));
      final back = PurchaseRecord.fromJson(r.toJson())!;
      expect(back.productId, r.productId);
      expect(back.serverVerifiedUntil, r.serverVerifiedUntil);
      expect(PurchaseRecord.fromJson({'productId': 1}), isNull);
    });
  });

  group('SubscriptionRepository', () {
    late FakeGateway gateway;
    late SharedPreferences prefs;
    var now = t0;

    Future<SubscriptionRepository> make(PurchaseVerifier verifier) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      gateway = FakeGateway();
      now = t0;
      return SubscriptionRepository(
        gateway: gateway,
        verifier: verifier,
        prefs: prefs,
        clock: () => now,
      );
    }

    BillingEvent purchased({String? product}) => BillingEvent(
      productId: product ?? BillingConfig.monthlyProductId,
      status: BillingEventStatus.purchased,
      purchaseToken: 'token',
    );

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('free by default and loads localised prices from the store', () async {
      final repo = await make(const UnconfiguredPurchaseVerifier());
      await repo.start();
      expect(repo.current.entitlement.isPro, isFalse);
      expect(
        repo.current.products.map((p) => p.priceText),
        containsAll(['₹49.00', '₹399.00']),
      );
      expect(gateway.restoreCalls, 1);
    });

    test(
      'billing unavailable leaves the app free and does not throw',
      () async {
        final repo = await make(const UnconfiguredPurchaseVerifier());
        gateway.available = false;
        await repo.start();
        expect(repo.current.phase, BillingPhase.unavailable);
        expect(repo.current.entitlement.isPro, isFalse);
      },
    );

    test('a purchase without a backend grants a time-limited, Play-confirmed entitlement and is acknowledged', () async {
      final repo = await make(FakeVerifier(configured: false));
      await repo.start();
      gateway.controller.add(purchased());
      await pump();
      await pump();
      expect(repo.current.entitlement.isPro, isTrue);
      expect(repo.current.entitlement.source, EntitlementSource.googlePlay);
      expect(gateway.completed.length, 1);
      // Grace expires -> free again, even though the flag is still stored.
      now = t0.add(const Duration(days: 4));
      await repo.refreshProducts();
      expect(repo.current.entitlement.isPro, isFalse);
    });

    test(
      'with a backend, verification success grants Pro until the server expiry',
      () async {
        final verifier = FakeVerifier(
          result: VerificationResult(
            active: true,
            expiresAt: t0.add(const Duration(days: 30)),
          ),
        );
        final repo = await make(verifier);
        await repo.start();
        gateway.controller.add(purchased());
        await pump();
        await pump();
        expect(verifier.calls, 1);
        expect(
          repo.current.entitlement.source,
          EntitlementSource.serverVerified,
        );
        expect(repo.current.entitlement.isPro, isTrue);
        expect(gateway.completed.length, 1);
      },
    );

    test('with a backend, a failed or offline verification neither grants Pro nor acknowledges', () async {
      final repo = await make(FakeVerifier(result: null));
      await repo.start();
      gateway.controller.add(purchased());
      await pump();
      await pump();
      expect(repo.current.entitlement.isPro, isFalse);
      expect(gateway.completed, isEmpty);
    });

    test(
      'an inactive subscription reported by the server clears the entitlement',
      () async {
        final repo = await make(
          FakeVerifier(result: const VerificationResult(active: false)),
        );
        await repo.start();
        gateway.controller.add(purchased());
        await pump();
        await pump();
        expect(repo.current.entitlement.isPro, isFalse);
      },
    );

    test('pending, canceled and error events never grant Pro', () async {
      final repo = await make(FakeVerifier(configured: false));
      await repo.start();
      gateway.controller.add(
        const BillingEvent(
          productId: 'spendwise_pro_monthly',
          status: BillingEventStatus.pending,
        ),
      );
      await pump();
      await pump();
      expect(repo.current.entitlement.isPro, isFalse);
      expect(repo.current.entitlement.pending, isTrue);
      gateway.controller.add(
        const BillingEvent(
          productId: 'spendwise_pro_monthly',
          status: BillingEventStatus.canceled,
        ),
      );
      await pump();
      expect(repo.current.message, contains('canceled'));
      gateway.controller.add(
        const BillingEvent(
          productId: '',
          status: BillingEventStatus.error,
          errorMessage: 'boom',
        ),
      );
      await pump();
      expect(repo.current.message, 'boom');
      expect(repo.current.entitlement.isPro, isFalse);
    });

    test('purchases of unknown products are ignored', () async {
      final repo = await make(FakeVerifier(configured: false));
      await repo.start();
      gateway.controller.add(purchased(product: 'some_other_product'));
      await pump();
      await pump();
      expect(repo.current.entitlement.isPro, isFalse);
    });

    test(
      'a stored entitlement is re-evaluated at startup, not trusted blindly',
      () async {
        final repo = await make(FakeVerifier(configured: false));
        await repo.start();
        gateway.controller.add(purchased());
        await pump();
        await pump();
        expect(repo.current.entitlement.isPro, isTrue);
        // New session 5 days later: restore finds nothing, so the old record lapses.
        final second = SubscriptionRepository(
          gateway: FakeGateway(),
          verifier: FakeVerifier(configured: false),
          prefs: prefs,
          clock: () => t0.add(const Duration(days: 5)),
        );
        await second.start();
        expect(second.current.entitlement.isPro, isFalse);
      },
    );

    test('manage-subscription link targets this app on Google Play', () async {
      final repo = await make(const UnconfiguredPurchaseVerifier());
      final uri = repo.manageSubscriptionUri();
      expect(uri.scheme, 'https');
      expect(uri.host, 'play.google.com');
      expect(uri.queryParameters['package'], BillingConfig.packageName);
    });
  });
}
