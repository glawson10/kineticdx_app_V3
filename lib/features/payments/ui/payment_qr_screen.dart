import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/clinic_context.dart';

class PaymentQrScreen extends StatelessWidget {
  /// If provided, used exactly.
  final String? qrData;

  /// Optional UI labels (not encoded unless you bake them into qrData).
  final String? iban;
  final String currency;
  final String? message;

  const PaymentQrScreen({
    super.key,
    this.qrData,
    this.iban,
    this.currency = 'CZK',
    this.message,
  });

  /// Czech QR Platba payload (SPD 1.0). Amount omitted intentionally.
  static String buildCzechQrPlatbaPayload({
    required String iban,
    String currency = 'CZK',
    required String message,
  }) {
    return 'SPD*1.0'
        '*ACC:$iban'
        '*CC:$currency'
        '*MSG:$message';
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId;

    // Phase 6+ : pull these from clinic billing settings
    final effectiveIban = iban ?? 'CZ3706000000000267372671';
    final effectiveMessage = message ?? 'Fundamental Recovery Consultation';

    final payload = qrData ??
        buildCzechQrPlatbaPayload(
          iban: effectiveIban,
          currency: currency,
          message: effectiveMessage,
        );

    // IMPORTANT:
    // This screen should NOT wrap itself in ClinicianShell.
    // The shell wraps this screen (otherwise you get double nav + double logout).
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min, // prevents vertical overflow
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ✅ Crisp QR: white container + gapless + high error correction.
                RepaintBoundary(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 10,
                          offset: Offset(0, 4),
                          color: Colors.black12,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 300,
                      gapless: true,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'Scan with your banking app.\nAmount entered manually.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),

                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank details',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),

                      const Text(
                        'IBAN:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(effectiveIban, style: const TextStyle(fontSize: 16)),

                      const SizedBox(height: 8),
                      Text('Currency: $currency', style: const TextStyle(fontSize: 16)),

                      const SizedBox(height: 8),
                      const Text(
                        'Message:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(effectiveMessage, style: const TextStyle(fontSize: 16)),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: payload));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('QR payload copied')),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy payload'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Clinic: $clinicId',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
