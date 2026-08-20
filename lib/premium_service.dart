import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class PremiumPurchaseService {
  PremiumPurchaseService({InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;

  static const productIds = <String>{
    'book_app_premium_monthly',
    'book_app_premium_yearly',
  };

  final InAppPurchase _store;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<bool> isAvailable() => _store.isAvailable();

  Future<List<ProductDetails>> loadProducts() async {
    final response = await _store.queryProductDetails(productIds);
    if (response.error != null) throw StateError(response.error!.message);
    return response.productDetails;
  }

  Future<void> start(ProductDetails product) {
    final purchaseParam = PurchaseParam(productDetails: product);
    return _store.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restore() => _store.restorePurchases();

  void listen({
    required Future<void> Function(PurchaseDetails purchase) onPurchase,
  }) {
    _subscription ??= _store.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        await onPurchase(purchase);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
      }
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
