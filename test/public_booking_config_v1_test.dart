// Commit 17: Tests for public mirror config parsing (no Firebase).
// Run: flutter test test/public_booking_config_v1_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kineticdx_app_v3/models/public_booking_config_v1.dart';

void main() {
  group('PublicBookingConfigV1', () {
    test('defaults match expected values', () {
      final c = PublicBookingConfigV1.defaults;
      expect(c.timezone, 'UTC');
      expect(c.slotStepMinutes, 15);
      expect(c.minNoticeMinutes, 0);
      expect(c.maxAdvanceDays, 90);
      expect(c.allowNewPatients, true);
      expect(c.requireEmail, true);
      expect(c.requirePhone, false);
      expect(c.cancellationPolicyHours, 24);
      expect(c.weeklyHours.length, 7);
      expect(c.weeklyHours['mon'], isEmpty);
      expect(c.weeklyHours['sun'], isEmpty);
    });

    test('fromDoc with null returns null', () {
      expect(PublicBookingConfigV1.fromDoc(null), isNull);
    });

    test('fromDoc with empty map returns null', () {
      expect(PublicBookingConfigV1.fromDoc({}), isNull);
    });

    test('fromDoc applies booking rules from mirror shape', () {
      final c = PublicBookingConfigV1.fromDoc({
        'jurisdiction': {'timezone': 'Europe/Prague', 'currencyCode': 'CZK'},
        'bookingRules': {
          'slotStepMinutes': 10,
          'minNoticeMinutes': 120,
          'maxAdvanceDays': 30,
          'requirePhone': true,
        },
        'weeklyHours': {
          'mon': [{'start': '09:00', 'end': '17:00'}],
          'tue': [],
          'wed': [],
          'thu': [],
          'fri': [],
          'sat': [],
          'sun': [],
        },
      });
      expect(c, isNotNull);
      expect(c!.timezone, 'Europe/Prague');
      expect(c.slotStepMinutes, 10);
      expect(c.minNoticeMinutes, 120);
      expect(c.maxAdvanceDays, 30);
      expect(c.requirePhone, true);
      expect(c.weeklyHours['mon']!.length, 1);
      expect(c.weeklyHours['mon']!.first.start, '09:00');
      expect(c.weeklyHours['mon']!.first.end, '17:00');
      expect(c.weeklyHours['sat'], isEmpty);
    });

    test('invalid slotStepMinutes falls back to 15', () {
      final c = PublicBookingConfigV1.fromDoc({
        'jurisdiction': {},
        'bookingRules': {'slotStepMinutes': 7},
        'weeklyHours': {},
      });
      expect(c, isNotNull);
      expect(c!.slotStepMinutes, 15);
    });

    test('weeklyHours parsing ignores bad entries', () {
      final c = PublicBookingConfigV1.fromDoc({
        'jurisdiction': {},
        'bookingRules': {},
        'weeklyHours': {
          'mon': [
            {'start': '09:00', 'end': '17:00'},
            {'start': 'bad', 'end': '17:00'},
            {'start': '10:00', 'end': '11:00'},
          ],
          'tue': [],
          'wed': [],
          'thu': [],
          'fri': [],
          'sat': [],
          'sun': [],
        },
      });
      expect(c, isNotNull);
      expect(c!.weeklyHours['mon']!.length, 2);
      expect(c.weeklyHours['mon']!.any((i) => i.start == '09:00' && i.end == '17:00'), true);
      expect(c.weeklyHours['mon']!.any((i) => i.start == '10:00' && i.end == '11:00'), true);
    });

    test('minNotice applied in parsed config', () {
      final c = PublicBookingConfigV1.fromDoc({
        'jurisdiction': {},
        'bookingRules': {'minNoticeMinutes': 480},
        'weeklyHours': {},
      });
      expect(c, isNotNull);
      expect(c!.minNoticeMinutes, 480);
    });
  });
}
