import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

enum BillingEventStatus { pending, purchased, restored, canceled, error }

/// Platform-neutral view of a purchase event.
class BillingEvent {
  const BillingEvent({
    required this.productId,
    required this.status,
    this.purchaseToken,
    this.errorMessage,
    this.handle,
  });

  final String productId;
  final BillingEventStatus status;
  final String? purchaseToken;
  final String? errorMessage;

  /// Opaque platform object needed to acknowledge/complete the purchase.
  final Object? handle;
}

class BillingProduct {
  const BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.priceText,
    required this.handle,
  });

  final String id;
  final String title;
  final String description;

  /// Localised price exactly as Google Play returns it.
  final String priceText;
  final Object handle;
}

class BillingProductsResult {
  const BillingProductsResult({required this.products, this.error});
  final List<BillingProduct> products;
  final String? error;
}

abstract class BillingGateway {
  Future<bool> isAvailable();
  Stream<BillingEvent> get events;
  Future<BillingProductsResult> loadProducts(Set<String> ids);
  Future<bool> buy(BillingProduct product);
  Future<void> restore();
  Future<void> complete(BillingEvent event);
  void dispose();
}

/// Gateway used when billing is unavailable (tests, unsupported devices).
class UnavailableBillingGateway implements BillingGateway {
  @override
  Stream<BillingEvent> get events => const Stream.empty();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<BillingProductsResult> loadProducts(Set<String> ids) async =>
      const BillingProductsResult(
        products: [],
        error: 'Google Play Billing is not available on this device.',
      );
  @override
  Future<bool> buy(BillingProduct product) async => false;
  @override
  Future<void> restore() async {}
  @override
  Future<void> complete(BillingEvent event) async {}
  @override
  void dispose() {}
}

class PlayBillingGateway implements BillingGateway {
  PlayBillingGateway([InAppPurchase? iap])
    : _iap = iap ?? InAppPurchase.instance;
  final InAppPurchase _iap;

  final _controller = StreamController<BillingEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  Stream<BillingEvent> get events {
    _sub ??= _iap.purchaseStream.listen(
      (list) {
        for (final p in list) {
          _controller.add(_map(p));
        }
      },
      onError: (Object e) => _controller.add(
        BillingEvent(
          productId: '',
          status: BillingEventStatus.error,
          errorMessage: '$e',
        ),
      ),
    );
    return _controller.stream;
  }

  BillingEvent _map(PurchaseDetails p) {
    final status = switch (p.status) {
      PurchaseStatus.pending => BillingEventStatus.pending,
      PurchaseStatus.purchased => BillingEventStatus.purchased,
      PurchaseStatus.restored => BillingEventStatus.restored,
      PurchaseStatus.canceled => BillingEventStatus.canceled,
      PurchaseStatus.error => BillingEventStatus.error,
    };
    return BillingEvent(
      productId: p.productID,
      status: status,
      purchaseToken: p.verificationData.serverVerificationData,
      errorMessage: p.error?.message,
      handle: p,
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BillingProductsResult> loadProducts(Set<String> ids) async {
    try {
      final r = await _iap.queryProductDetails(ids);
      final products = [
        for (final d in r.productDetails)
          BillingProduct(
            id: d.id,
            title: d.title,
            description: d.description,
            priceText: d.price,
            handle: d,
          ),
      ];
      String? error = r.error?.message;
      if (products.isEmpty && error == null && r.notFoundIDs.isNotEmpty) {
        error =
            'Subscriptions are not set up in Google Play yet (${r.notFoundIDs.join(', ')}).';
      }
      return BillingProductsResult(products: products, error: error);
    } catch (e) {
      return BillingProductsResult(
        products: const [],
        error: 'Could not reach Google Play. Check your connection.',
      );
    }
  }

  @override
  Future<bool> buy(BillingProduct product) async {
    final details = product.handle as ProductDetails;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(BillingEvent event) async {
    final p = event.handle;
    if (p is PurchaseDetails && p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
