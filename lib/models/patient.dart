import 'package:cloud_firestore/cloud_firestore.dart';

class Patient {
  final String id;
  final String clinicId;

  // Identity
  final String firstName;
  final String lastName;
  final String? preferredName;
  final DateTime? dateOfBirth; // canonical
  final String? sex;
  final String? pronouns;
  final String? language;

  // Contact
  final String? email;
  final String? phone;
  final String? preferredContactMethod; // "sms"|"email"|"call"|null
  final Address? address;
  final Consent? consent;

  // Emergency contact
  final EmergencyContact? emergencyContact;

  // Referrer
  final Referrer? referrer;

  // Billing
  final Billing? billing;

  // Admin/workflow
  final List<String> tags;
  final List<String> alerts;
  final String? adminNotes;

  // Status
  final bool active;
  final bool archived;
  final DateTime? archivedAt;

  // Retention
  final DateTime? retentionUntil;

  // Audit/system
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdByUid;
  final String? updatedByUid;
  final int? schemaVersion;

  Patient({
    required this.id,
    required this.clinicId,
    required this.firstName,
    required this.lastName,
    this.preferredName,
    this.dateOfBirth,
    this.sex,
    this.pronouns,
    this.language,
    this.email,
    this.phone,
    this.preferredContactMethod,
    this.address,
    this.consent,
    this.emergencyContact,
    this.referrer,
    this.billing,
    required this.tags,
    required this.alerts,
    this.adminNotes,
    required this.active,
    required this.archived,
    this.archivedAt,
    this.retentionUntil,
    this.createdAt,
    this.updatedAt,
    this.createdByUid,
    this.updatedByUid,
    this.schemaVersion,
  });

  // ---------- Helpers ----------
  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    return null;
  }

  static String? _asString(dynamic v) => v?.toString();

  static List<String> _asStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  static bool _asBool(dynamic v) => v == true;

  factory Patient.fromFirestore(String id, Map<String, dynamic> data) {
    // Canonical nested fields (preferred)
    final identity = _asMap(data['identity']) ?? const <String, dynamic>{};
    final contact = _asMap(data['contact']) ?? const <String, dynamic>{};
    final status = _asMap(data['status']) ?? const <String, dynamic>{};
    final retention = _asMap(data['retention']) ?? const <String, dynamic>{};

    // Dual-read: fallback to legacy flat keys if nested missing
    final firstName = (_asString(identity['firstName']) ?? _asString(data['firstName']) ?? '').trim();
    final lastName = (_asString(identity['lastName']) ?? _asString(data['lastName']) ?? '').trim();

    final dobValue =
        identity.containsKey('dateOfBirth') ? identity['dateOfBirth'] : (data.containsKey('dob') ? data['dob'] : data['dateOfBirth']);
    final dateOfBirth = _toDate(dobValue);

    final email = _asString(contact['email']) ?? (data['email'] as String?);
    final phone = _asString(contact['phone']) ?? (data['phone'] as String?);

    final archivedAt = _toDate(status['archivedAt'] ?? data['archivedAt']);
    final createdAt = _toDate(data['createdAt']);
    final updatedAt = _toDate(data['updatedAt']);

    final retentionUntil = _toDate(retention['retentionUntil'] ?? data['retentionUntil']);

    final addressMap = _asMap(contact['address']);
    final consentMap = _asMap(contact['consent']);

    final emergencyMap = _asMap(data['emergencyContact']);
    final referrerMap = _asMap(data['referrer']);
    final billingMap = _asMap(data['billing']);

    return Patient(
      id: id,
      clinicId: _asString(data['clinicId']) ?? '',
      firstName: firstName,
      lastName: lastName,
      preferredName: _asString(identity['preferredName']),
      dateOfBirth: dateOfBirth,
      sex: _asString(identity['sex']),
      pronouns: _asString(identity['pronouns']),
      language: _asString(identity['language']),
      email: email,
      phone: phone,
      preferredContactMethod: _asString(contact['preferredMethod']),
      address: addressMap != null ? Address.fromMap(addressMap) : null,
      consent: consentMap != null ? Consent.fromMap(consentMap) : null,
      emergencyContact: emergencyMap != null ? EmergencyContact.fromMap(emergencyMap) : null,
      referrer: referrerMap != null ? Referrer.fromMap(referrerMap) : null,
      billing: billingMap != null ? Billing.fromMap(billingMap) : null,
      tags: _asStringList(data['tags']),
      alerts: _asStringList(data['alerts']),
      adminNotes: _asString(data['adminNotes']),
      active: _asBool(status['active'] ?? data['active']),
      archived: _asBool(status['archived'] ?? data['archived']),
      archivedAt: archivedAt,
      retentionUntil: retentionUntil,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdByUid: _asString(data['createdByUid']),
      updatedByUid: _asString(data['updatedByUid']),
      schemaVersion: (data['schemaVersion'] is int) ? data['schemaVersion'] as int : null,
    );
  }
}

class Address {
  final String? line1;
  final String? line2;
  final String? city;
  final String? postcode;
  final String? country;

  Address({this.line1, this.line2, this.city, this.postcode, this.country});

  factory Address.fromMap(Map<String, dynamic> m) => Address(
        line1: m['line1']?.toString(),
        line2: m['line2']?.toString(),
        city: m['city']?.toString(),
        postcode: m['postcode']?.toString(),
        country: m['country']?.toString(),
      );
}

class Consent {
  final bool? sms;
  final bool? email;

  Consent({this.sms, this.email});

  factory Consent.fromMap(Map<String, dynamic> m) => Consent(
        sms: m['sms'] == null ? null : m['sms'] == true,
        email: m['email'] == null ? null : m['email'] == true,
      );
}

class EmergencyContact {
  final String? name;
  final String? relationship;
  final String? phone;

  EmergencyContact({this.name, this.relationship, this.phone});

  factory EmergencyContact.fromMap(Map<String, dynamic> m) => EmergencyContact(
        name: m['name']?.toString(),
        relationship: m['relationship']?.toString(),
        phone: m['phone']?.toString(),
      );
}

class Referrer {
  final String? source; // self|gp|insurer|employer|sportsClub|other
  final String? name;
  final String? org;
  final String? phone;
  final String? email;

  Referrer({this.source, this.name, this.org, this.phone, this.email});

  factory Referrer.fromMap(Map<String, dynamic> m) => Referrer(
        source: m['source']?.toString(),
        name: m['name']?.toString(),
        org: m['org']?.toString(),
        phone: m['phone']?.toString(),
        email: m['email']?.toString(),
      );
}

class Billing {
  final bool? isDifferent;
  final String? name;
  final Address? address;
  final Insurer? insurer;
  final String? invoiceNotes;

  Billing({this.isDifferent, this.name, this.address, this.insurer, this.invoiceNotes});

  factory Billing.fromMap(Map<String, dynamic> m) => Billing(
        isDifferent: m['isDifferent'] == null ? null : m['isDifferent'] == true,
        name: m['name']?.toString(),
        address: (m['address'] is Map<String, dynamic>) ? Address.fromMap(m['address']) : null,
        insurer: (m['insurer'] is Map<String, dynamic>) ? Insurer.fromMap(m['insurer']) : null,
        invoiceNotes: m['invoiceNotes']?.toString(),
      );
}

class Insurer {
  final String? provider;
  final String? policyNumber;

  Insurer({this.provider, this.policyNumber});

  factory Insurer.fromMap(Map<String, dynamic> m) => Insurer(
        provider: m['provider']?.toString(),
        policyNumber: m['policyNumber']?.toString(),
      );
}
