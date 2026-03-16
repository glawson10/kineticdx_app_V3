import 'package:cloud_firestore/cloud_firestore.dart';

class BillingGeneralSettings {
  const BillingGeneralSettings({
    this.invoicePrefix = '',
    this.nextInvoiceNumber,
    this.defaultDueDays,
    this.currency,
    this.taxInclusivePricing,
    this.updatedAt,
    this.schemaVersion,
    this.businessDisplayName,
    this.businessLegalName,
    this.businessAddress,
    this.businessCountry,
    this.registrationNumber,
    this.taxId,
    this.businessPhone,
    this.businessEmail,
    this.businessWebsite,
    this.defaultFooterText,
    this.defaultInvoiceNotes,
    this.defaultLocale,
    this.invoiceTitle,
    this.showLogoOnInvoice,
    this.showPractitionerOnInvoice,
    this.showBusinessContactOnInvoice,
    this.groupTaxLinesOnInvoice,
  });

  final String invoicePrefix;
  final int? nextInvoiceNumber;
  final int? defaultDueDays;
  final String? currency;
  final bool? taxInclusivePricing;
  final DateTime? updatedAt;
  final int? schemaVersion;
  final String? businessDisplayName;
  final String? businessLegalName;
  final String? businessAddress;
  final String? businessCountry;
  final String? registrationNumber;
  final String? taxId;
  final String? businessPhone;
  final String? businessEmail;
  final String? businessWebsite;
  final String? defaultFooterText;
  final String? defaultInvoiceNotes;
  final String? defaultLocale;
  final String? invoiceTitle;
  final bool? showLogoOnInvoice;
  final bool? showPractitionerOnInvoice;
  final bool? showBusinessContactOnInvoice;
  final bool? groupTaxLinesOnInvoice;

  static String? _optStr(dynamic v) {
    if (v == null) return null;
    final s = (v as String).trim();
    return s.isEmpty ? null : s;
  }

  static bool? _optBool(dynamic v) {
    if (v is bool) return v;
    return null;
  }

  factory BillingGeneralSettings.fromDoc(Map<String, dynamic> data) {
    Timestamp? ts;
    final u = data['updatedAt'];
    if (u is Timestamp) {
      ts = u;
    }
    return BillingGeneralSettings(
      invoicePrefix: (data['invoicePrefix'] ?? '').toString().trim(),
      nextInvoiceNumber: (data['nextInvoiceNumber'] as num?)?.toInt(),
      defaultDueDays: (data['defaultDueDays'] as num?)?.toInt(),
      currency: _optStr(data['currency']),
      taxInclusivePricing: _optBool(data['taxInclusivePricing']),
      updatedAt: ts?.toDate(),
      schemaVersion: (data['schemaVersion'] as num?)?.toInt(),
      businessDisplayName: _optStr(data['businessDisplayName']),
      businessLegalName: _optStr(data['businessLegalName']),
      businessAddress: _optStr(data['businessAddress']),
      businessCountry: _optStr(data['businessCountry']),
      registrationNumber: _optStr(data['registrationNumber']),
      taxId: _optStr(data['taxId']),
      businessPhone: _optStr(data['businessPhone']),
      businessEmail: _optStr(data['businessEmail']),
      businessWebsite: _optStr(data['businessWebsite']),
      defaultFooterText: _optStr(data['defaultFooterText']),
      defaultInvoiceNotes: _optStr(data['defaultInvoiceNotes']),
      defaultLocale: _optStr(data['defaultLocale']),
      invoiceTitle: _optStr(data['invoiceTitle']),
      showLogoOnInvoice: _optBool(data['showLogoOnInvoice']),
      showPractitionerOnInvoice: _optBool(data['showPractitionerOnInvoice']),
      showBusinessContactOnInvoice: _optBool(data['showBusinessContactOnInvoice']),
      groupTaxLinesOnInvoice: _optBool(data['groupTaxLinesOnInvoice']),
    );
  }
}

class BillingTax {
  const BillingTax({
    required this.id,
    required this.name,
    required this.rate,
    required this.active,
  });
  final String id;
  final String name;
  final double rate;
  final bool active;

  factory BillingTax.fromDoc(String id, Map<String, dynamic> data) => BillingTax(
        id: id,
        name: (data['name'] ?? '').toString(),
        rate: (data['rate'] as num?)?.toDouble() ?? 0,
        active: data['active'] == true,
      );
}

class BillingPaymentType {
  const BillingPaymentType({
    required this.id,
    required this.name,
    required this.active,
  });
  final String id;
  final String name;
  final bool active;

  factory BillingPaymentType.fromDoc(String id, Map<String, dynamic> data) =>
      BillingPaymentType(
        id: id,
        name: (data['name'] ?? '').toString(),
        active: data['active'] == true,
      );
}

class BillingCatalogItem {
  const BillingCatalogItem({
    required this.id,
    required this.name,
    required this.price,
    required this.active,
    this.taxId,
    this.stock,
  });
  final String id;
  final String name;
  final double price;
  final bool active;
  final String? taxId;
  final int? stock;

  factory BillingCatalogItem.fromDoc(String id, Map<String, dynamic> data) =>
      BillingCatalogItem(
        id: id,
        name: (data['name'] ?? '').toString(),
        price: (data['price'] as num?)?.toDouble() ?? 0,
        active: data['active'] == true,
        taxId: (data['taxId'] as String?)?.trim().isNotEmpty == true
            ? (data['taxId'] as String).trim()
            : null,
        stock: (data['stock'] as num?)?.toInt(),
      );
}

class InvoiceLine {
  const InvoiceLine({
    required this.type,
    required this.itemId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    required this.total,
    this.discount = 0,
  });

  final String type;
  final String itemId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double taxRate;
  final double total;
  final double discount;

  Map<String, dynamic> toJson() => {
        'type': type,
        'itemId': itemId,
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'taxRate': taxRate,
        'discount': discount,
        'total': total,
      };

  factory InvoiceLine.fromJson(Map<String, dynamic> data) => InvoiceLine(
        type: (data['type'] ?? 'service').toString(),
        itemId: (data['itemId'] ?? '').toString(),
        description: (data['description'] ?? '').toString(),
        quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
        taxRate: (data['taxRate'] as num?)?.toDouble() ?? 0,
        discount: (data['discount'] as num?)?.toDouble() ?? 0,
        total: (data['total'] as num?)?.toDouble() ?? 0,
      );
}

/// Frozen snapshot at issue time; used for render so issued invoices are unchanged by settings edits.
class IssuedInvoiceSnapshot {
  const IssuedInvoiceSnapshot({
    this.sellerIdentity,
    this.buyerIdentity,
    this.numberingResult,
    this.taxProfileSnapshot,
    this.currencyLocale,
    this.footerTemplateSnapshot,
    this.lineItemPricingSnapshot,
    this.taxBreakdownSnapshot,
  });

  final Map<String, dynamic>? sellerIdentity;
  final Map<String, dynamic>? buyerIdentity;
  final Map<String, dynamic>? numberingResult;
  final Map<String, dynamic>? taxProfileSnapshot;
  final Map<String, dynamic>? currencyLocale;
  final Map<String, dynamic>? footerTemplateSnapshot;
  final List<dynamic>? lineItemPricingSnapshot;
  final Map<String, dynamic>? taxBreakdownSnapshot;

  static IssuedInvoiceSnapshot? fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    return IssuedInvoiceSnapshot(
      sellerIdentity: data['sellerIdentity'] as Map<String, dynamic>?,
      buyerIdentity: data['buyerIdentity'] as Map<String, dynamic>?,
      numberingResult: data['numberingResult'] as Map<String, dynamic>?,
      taxProfileSnapshot: data['taxProfileSnapshot'] as Map<String, dynamic>?,
      currencyLocale: data['currencyLocale'] as Map<String, dynamic>?,
      footerTemplateSnapshot: data['footerTemplateSnapshot'] as Map<String, dynamic>?,
      lineItemPricingSnapshot: data['lineItemPricingSnapshot'] as List<dynamic>?,
      taxBreakdownSnapshot: data['taxBreakdownSnapshot'] as Map<String, dynamic>?,
    );
  }
}

class BillingInvoice {
  const BillingInvoice({
    required this.id,
    required this.patientId,
    required this.status,
    required this.total,
    required this.taxTotal,
    required this.subtotal,
    required this.balanceDue,
    required this.amountPaid,
    required this.lineItems,
    this.appointmentId,
    this.displayNumber,
    this.dueDate,
    this.currency,
    this.issuedAt,
    this.issuedSnapshot,
  });

  final String id;
  final String patientId;
  final String? appointmentId;
  final String status;
  final double subtotal;
  final double taxTotal;
  final double total;
  final double amountPaid;
  final double balanceDue;
  final List<InvoiceLine> lineItems;
  final String? displayNumber;
  final DateTime? dueDate;
  final String? currency;
  final DateTime? issuedAt;
  final IssuedInvoiceSnapshot? issuedSnapshot;

  /// For issued invoices, use snapshot so rendering is unchanged by settings. Otherwise use stored field.
  String? get effectiveDisplayNumber {
    if (status == 'issued' || status == 'paid') {
      final numResult = issuedSnapshot?.numberingResult;
      if (numResult != null) {
        final n = numResult['displayNumber'];
        if (n != null && n.toString().trim().isNotEmpty) return n.toString().trim();
      }
    }
    return displayNumber;
  }

  /// For issued invoices, use snapshot totals so rendering is unchanged by settings.
  double get effectiveSubtotal {
    if (status == 'issued' || status == 'paid') {
      final t = issuedSnapshot?.taxBreakdownSnapshot;
      if (t != null && t['subtotal'] != null) return (t['subtotal'] as num).toDouble();
    }
    return subtotal;
  }

  double get effectiveTaxTotal {
    if (status == 'issued' || status == 'paid') {
      final t = issuedSnapshot?.taxBreakdownSnapshot;
      if (t != null && t['taxTotal'] != null) return (t['taxTotal'] as num).toDouble();
    }
    return taxTotal;
  }

  double get effectiveTotal {
    if (status == 'issued' || status == 'paid') {
      final t = issuedSnapshot?.taxBreakdownSnapshot;
      if (t != null && t['total'] != null) return (t['total'] as num).toDouble();
    }
    return total;
  }

  /// For issued invoices, prefer line-item snapshot for render; otherwise use lineItems.
  List<InvoiceLine> get effectiveLineItems {
    if (status == 'issued' || status == 'paid') {
      final snap = issuedSnapshot?.lineItemPricingSnapshot;
      if (snap != null && snap.isNotEmpty) {
        return snap
            .whereType<Map>()
            .map((e) => InvoiceLine.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
    return lineItems;
  }

  /// Seller display name from snapshot when issued.
  String? get effectiveSellerDisplayName {
    if (status == 'issued' || status == 'paid') {
      final s = issuedSnapshot?.sellerIdentity;
      if (s != null) {
        final n = s['businessDisplayName'] ?? s['businessLegalName'];
        if (n != null && n.toString().trim().isNotEmpty) return n.toString().trim();
      }
    }
    return null;
  }

  /// Currency from snapshot when issued.
  String? get effectiveCurrency {
    if (status == 'issued' || status == 'paid') {
      final c = issuedSnapshot?.currencyLocale;
      if (c != null && c['currency'] != null) return c['currency'].toString().trim();
    }
    return currency;
  }

  factory BillingInvoice.fromDoc(String id, Map<String, dynamic> data) {
    DateTime? dueDate;
    final due = data['dueDate'];
    if (due is Timestamp) {
      dueDate = due.toDate();
    }
    DateTime? issuedAt;
    final issuedAtVal = data['issuedAt'];
    if (issuedAtVal is Timestamp) {
      issuedAt = issuedAtVal.toDate();
    }
    final issuedSnapshot = IssuedInvoiceSnapshot.fromMap(
      data['issuedSnapshot'] as Map<String, dynamic>?,
    );
    return BillingInvoice(
      id: id,
      patientId: (data['patientId'] ?? '').toString(),
      appointmentId: (data['appointmentId'] as String?)?.trim(),
      status: (data['status'] ?? 'draft').toString(),
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0,
      taxTotal: (data['taxTotal'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      balanceDue: (data['balanceDue'] as num?)?.toDouble() ?? 0,
      lineItems: ((data['lineItems'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => InvoiceLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      displayNumber: (data['displayNumber'] as String?)?.trim().isNotEmpty == true
          ? (data['displayNumber'] as String).trim()
          : null,
      dueDate: dueDate,
      currency: (data['currency'] as String?)?.trim().isNotEmpty == true
          ? (data['currency'] as String).trim()
          : null,
      issuedAt: issuedAt,
      issuedSnapshot: issuedSnapshot,
    );
  }
}

class RecentActivityItem {
  const RecentActivityItem({
    required this.invoiceId,
    required this.displayNumber,
    required this.status,
    required this.updatedAt,
  });
  final String invoiceId;
  final String displayNumber;
  final String status;
  final String updatedAt;

  factory RecentActivityItem.fromJson(Map<String, dynamic> data) => RecentActivityItem(
        invoiceId: data['invoiceId'] as String? ?? '',
        displayNumber: data['displayNumber'] as String? ?? '',
        status: data['status'] as String? ?? '',
        updatedAt: data['updatedAt'] as String? ?? '',
      );
}

class BillingSummary {
  const BillingSummary({
    required this.revenueToday,
    required this.revenueMonth,
    required this.outstandingInvoices,
    this.recentActivity = const [],
  });
  final double revenueToday;
  final double revenueMonth;
  final double outstandingInvoices;
  final List<RecentActivityItem> recentActivity;

  factory BillingSummary.fromJson(Map<String, dynamic> data) {
    final raw = data['recentActivity'];
    List<RecentActivityItem> activity = const [];
    if (raw is List) {
      activity = raw
          .map((e) => RecentActivityItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return BillingSummary(
      revenueToday: (data['revenueToday'] as num?)?.toDouble() ?? 0,
      revenueMonth: (data['revenueMonth'] as num?)?.toDouble() ?? 0,
      outstandingInvoices: (data['outstandingInvoices'] as num?)?.toDouble() ?? 0,
      recentActivity: activity,
    );
  }
}

class AgedReceivables {
  const AgedReceivables({
    required this.current,
    required this.days30,
    required this.days60,
    required this.days90plus,
  });
  final double current;
  final double days30;
  final double days60;
  final double days90plus;

  factory AgedReceivables.fromJson(Map<String, dynamic> data) {
    final b = Map<String, dynamic>.from((data['buckets'] as Map?) ?? const {});
    return AgedReceivables(
      current: (b['current'] as num?)?.toDouble() ?? 0,
      days30: (b['days30'] as num?)?.toDouble() ?? 0,
      days60: (b['days60'] as num?)?.toDouble() ?? 0,
      days90plus: (b['days90plus'] as num?)?.toDouble() ?? 0,
    );
  }
}
