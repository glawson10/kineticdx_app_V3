import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../features/billing/models/billing_models.dart';

class BillingRepository {
  BillingRepository(this._db, {FirebaseFunctions? functions})
      : _fn = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west3');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  Stream<List<BillingInvoice>> watchInvoices(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    return _db
        .collection('clinics')
        .doc(c)
        .collection('invoices')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => BillingInvoice.fromDoc(d.id, d.data())).toList());
  }

  Stream<List<BillingTax>> watchTaxes(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    return _db
        .collection('clinics')
        .doc(c)
        .collection('taxes')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BillingTax.fromDoc(d.id, d.data())).toList());
  }

  Stream<List<BillingPaymentType>> watchPaymentTypes(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    return _db
        .collection('clinics')
        .doc(c)
        .collection('paymentTypes')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BillingPaymentType.fromDoc(d.id, d.data())).toList());
  }

  Stream<List<BillingCatalogItem>> watchBillableItems(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    return _db
        .collection('clinics')
        .doc(c)
        .collection('billableItems')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BillingCatalogItem.fromDoc(d.id, d.data())).toList());
  }

  Stream<List<BillingCatalogItem>> watchProducts(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    return _db
        .collection('clinics')
        .doc(c)
        .collection('products')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BillingCatalogItem.fromDoc(d.id, d.data())).toList());
  }

  /// Path: clinics/{clinicId}/billing/_/settings/general. Requires billing read permission.
  static const _billingSettingsTimeout = Duration(seconds: 15);
  static const _billingSettingsGetTimeout = Duration(seconds: 8);

  /// One-time read for initial load (avoids stream not emitting). Use for config panes; retry on failure.
  Future<BillingGeneralSettings?> getBillingGeneralSettingsOnce(String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) return null;
    final ref = _db
        .collection('clinics')
        .doc(c)
        .collection('billing')
        .doc('_')
        .collection('settings')
        .doc('general');
    final snap = await ref.get().timeout(
          _billingSettingsGetTimeout,
          onTimeout: () => throw TimeoutException(
            'Billing settings load timed out after ${_billingSettingsGetTimeout.inSeconds}s. Check connection and billing read permission.',
          ),
        );
    if (!snap.exists || snap.data() == null) return null;
    return BillingGeneralSettings.fromDoc(Map<String, dynamic>.from(snap.data()!));
  }

  Stream<BillingGeneralSettings?> watchBillingGeneralSettings(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(null);
    return _db
        .collection('clinics')
        .doc(c)
        .collection('billing')
        .doc('_')
        .collection('settings')
        .doc('general')
        .snapshots()
        .timeout(
          _billingSettingsTimeout,
          onTimeout: (sink) => sink.addError(
            TimeoutException('Billing settings load timed out after ${_billingSettingsTimeout.inSeconds}s. Check connection and billing read permission.'),
          ),
        )
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return BillingGeneralSettings.fromDoc(Map<String, dynamic>.from(snap.data()!));
    });
  }

  /// Updates billing general settings. Requires billing write permission (enforced by backend).
  Future<void> updateBillingGeneralSettings(String clinicId, Map<String, dynamic> patch) async {
    await _fn.httpsCallable('billingUpdateSettingsFn').call({
      'clinicId': clinicId.trim(),
      'patch': patch,
    });
  }

  Future<void> upsertTax(String clinicId, {String? taxId, required Map<String, dynamic> patch}) async {
    await _fn.httpsCallable('settingsUpsertTax').call({
      'clinicId': clinicId,
      if ((taxId ?? '').trim().isNotEmpty) 'taxId': taxId!.trim(),
      'patch': patch,
    });
  }

  Future<void> upsertPaymentType(String clinicId, {String? paymentTypeId, required Map<String, dynamic> patch}) async {
    await _fn.httpsCallable('settingsUpsertPaymentType').call({
      'clinicId': clinicId,
      if ((paymentTypeId ?? '').trim().isNotEmpty) 'paymentTypeId': paymentTypeId!.trim(),
      'patch': patch,
    });
  }

  Future<void> upsertBillableItem(String clinicId, {String? itemId, required Map<String, dynamic> patch}) async {
    await _fn.httpsCallable('settingsUpsertBillableItem').call({
      'clinicId': clinicId,
      if ((itemId ?? '').trim().isNotEmpty) 'itemId': itemId!.trim(),
      'patch': patch,
    });
  }

  Future<void> upsertProduct(String clinicId, {String? productId, required Map<String, dynamic> patch}) async {
    await _fn.httpsCallable('settingsUpsertProduct').call({
      'clinicId': clinicId,
      if ((productId ?? '').trim().isNotEmpty) 'productId': productId!.trim(),
      'patch': patch,
    });
  }

  Future<String> createInvoice({
    required String clinicId,
    required String patientId,
    String? appointmentId,
    required List<InvoiceLine> lineItems,
    double invoiceDiscount = 0,
  }) async {
    final res = await _fn.httpsCallable('billingCreateInvoiceFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      if ((appointmentId ?? '').trim().isNotEmpty) 'appointmentId': appointmentId,
      'lineItems': lineItems.map((e) => e.toJson()).toList(),
      'invoiceDiscount': invoiceDiscount,
    });
    final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
    return (data['invoiceId'] ?? '').toString();
  }

  Future<void> updateInvoice({
    required String clinicId,
    required String invoiceId,
    required Map<String, dynamic> patch,
  }) async {
    await _fn.httpsCallable('billingUpdateInvoiceFn').call({
      'clinicId': clinicId,
      'invoiceId': invoiceId,
      'patch': patch,
    });
  }

  Future<void> recordPayment({
    required String clinicId,
    required String invoiceId,
    required String paymentTypeId,
    required double amount,
  }) async {
    await _fn.httpsCallable('billingRecordPaymentFn').call({
      'clinicId': clinicId,
      'invoiceId': invoiceId,
      'paymentTypeId': paymentTypeId,
      'amount': amount,
    });
  }

  Future<void> createInvoiceFromAppointment({
    required String clinicId,
    required String appointmentId,
    required String patientId,
    required List<InvoiceLine> lineItems,
  }) async {
    await _fn.httpsCallable('billingCreateInvoiceFromAppointmentFn').call({
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      'patientId': patientId,
      'lineItems': lineItems.map((e) => e.toJson()).toList(),
    });
  }

  Future<void> issueCreditNote({
    required String clinicId,
    required String invoiceId,
    required double amount,
    required String reason,
  }) async {
    await _fn.httpsCallable('billingIssueCreditNoteFn').call({
      'clinicId': clinicId,
      'invoiceId': invoiceId,
      'amount': amount,
      'reason': reason,
    });
  }

  Future<void> refundPayment({
    required String clinicId,
    required String paymentId,
    required double amount,
    required String reason,
  }) async {
    await _fn.httpsCallable('billingRefundPaymentFn').call({
      'clinicId': clinicId,
      'paymentId': paymentId,
      'amount': amount,
      'reason': reason,
    });
  }

  Future<BillingSummary> getSummary(String clinicId) async {
    final res = await _fn.httpsCallable('billingGetSummaryFn').call({'clinicId': clinicId});
    return BillingSummary.fromJson(Map<String, dynamic>.from((res.data as Map?) ?? const {}));
  }

  Future<AgedReceivables> getAgedReceivables(String clinicId) async {
    final res = await _fn.httpsCallable('billingGetAgedReceivablesFn').call({'clinicId': clinicId});
    return AgedReceivables.fromJson(Map<String, dynamic>.from((res.data as Map?) ?? const {}));
  }

  Future<Map<String, dynamic>> createInvoicePaymentLink({
    required String clinicId,
    required String invoiceId,
  }) async {
    final res = await _fn.httpsCallable('billingCreateInvoicePaymentLinkFn').call({
      'clinicId': clinicId,
      'invoiceId': invoiceId,
    });
    return Map<String, dynamic>.from((res.data as Map?) ?? const {});
  }

  /// Generate and store PDF for an issued/paid invoice (issuedSnapshot only). Fails if snapshot missing.
  Future<Map<String, dynamic>> generateInvoicePdf({
    required String clinicId,
    required String invoiceId,
  }) async {
    final res = await _fn.httpsCallable('billingGenerateInvoicePdfFn').call({
      'clinicId': clinicId,
      'invoiceId': invoiceId,
    });
    return Map<String, dynamic>.from((res.data as Map?) ?? const {});
  }

  /// Get a short-lived signed download URL for the invoice PDF (issued/paid only).
  Future<String?> getInvoicePdfDownloadUrl({
    required String clinicId,
    required String invoiceId,
  }) async {
    final res = await _fn.httpsCallable('billingGetInvoicePdfDownloadUrlFn').call({
      'clinicId': clinicId,
      'invoiceId': invoiceId,
    });
    final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
    return data['url'] as String?;
  }
}
