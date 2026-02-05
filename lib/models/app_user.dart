import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String? phone;
  final String? defaultClinicId;
  final Map<String, dynamic> onboarding;
  final Timestamp createdAt;
  final Timestamp lastSeenAt;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.defaultClinicId,
    required this.onboarding,
    required this.createdAt,
    required this.lastSeenAt,
  });

  factory AppUser.fromJson(String uid, Map<String, dynamic> json) {
    final onboardingRaw = json['onboarding'];

    return AppUser(
      uid: uid,
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: json['phone'] as String?,
      defaultClinicId: json['defaultClinicId'] as String?,
      onboarding: onboardingRaw is Map
          ? Map<String, dynamic>.from(onboardingRaw)
          : <String, dynamic>{},
      createdAt: (json['createdAt'] as Timestamp?) ?? Timestamp.now(),
      lastSeenAt: (json['lastSeenAt'] as Timestamp?) ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'email': email,
        'phone': phone,
        'defaultClinicId': defaultClinicId,
        'onboarding': onboarding,
        'createdAt': createdAt,
        'lastSeenAt': lastSeenAt,
      };
}
