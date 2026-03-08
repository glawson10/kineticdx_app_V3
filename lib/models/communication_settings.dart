// lib/models/communication_settings.dart
//
// SETTINGS_SYSTEM §4.8: clinics/{clinicId}/settings/communication.
// Read via callable (settingsGetCommunicationSettings); write via callable only.

/// Allowed values for default reminder channel (SETTINGS_SYSTEM §4.8).
enum DefaultReminderChannel {
  email,
  sms,
  both,
  none,
}

extension DefaultReminderChannelX on DefaultReminderChannel {
  String get value {
    switch (this) {
      case DefaultReminderChannel.email:
        return 'email';
      case DefaultReminderChannel.sms:
        return 'sms';
      case DefaultReminderChannel.both:
        return 'both';
      case DefaultReminderChannel.none:
        return 'none';
    }
  }

  static DefaultReminderChannel fromString(String? v) {
    switch (v) {
      case 'email':
        return DefaultReminderChannel.email;
      case 'sms':
        return DefaultReminderChannel.sms;
      case 'both':
        return DefaultReminderChannel.both;
      case 'none':
        return DefaultReminderChannel.none;
      default:
        return DefaultReminderChannel.email;
    }
  }
}

class CommunicationSettings {
  const CommunicationSettings({
    this.defaultReplyToEmail = '',
    this.defaultReminderChannel = DefaultReminderChannel.email,
  });

  final String defaultReplyToEmail;
  final DefaultReminderChannel defaultReminderChannel;

  static const defaults = CommunicationSettings();

  /// From callable/Firestore doc (settings/communication).
  factory CommunicationSettings.fromDoc(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return defaults;
    final replyTo = data['defaultReplyToEmail'];
    final replyStr = replyTo is String ? replyTo : (replyTo?.toString() ?? '');
    final channelRaw = data['defaultReminderChannel'];
    final channel = DefaultReminderChannelX.fromString(
      channelRaw is String ? channelRaw : channelRaw?.toString(),
    );
    return CommunicationSettings(
      defaultReplyToEmail: replyStr,
      defaultReminderChannel: channel,
    );
  }

  /// Patch shape for settingsUpdateCommunicationSettings callable.
  Map<String, dynamic> toPatch() {
    return <String, dynamic>{
      'defaultReplyToEmail': defaultReplyToEmail.trim(),
      'defaultReminderChannel': defaultReminderChannel.value,
    };
  }
}
