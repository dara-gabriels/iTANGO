// lib/features/events/presentation/my_ticket_screen.dart
//
// FOUND MISSING DURING FULL-STACK VERIFICATION: the staff-checkin Edge
// Function and the organizer web dashboard's QR scanner both assume the
// attendee can SHOW a QR code on their phone — but until this file, no
// screen in the app ever rendered `ticket_purchases.qr_code`. The entire
// staff-scan check-in path was unusable in practice despite being "built"
// on the backend and web sides. This is that missing piece.
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/itango_theme.dart';
import '../domain/event_detail_models.dart';

class MyTicketScreen extends StatelessWidget {
  const MyTicketScreen({super.key, required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final qrCode = event.userTicketQrCode;

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(title: const Text('My Ticket')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ItangoSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.title,
                style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 22, fontWeight: FontWeight.w700, color: ItangoColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ItangoSpacing.s2),
              const Text(
                'Show this to event staff at the door',
                style: TextStyle(color: ItangoColors.textSecondary),
              ),
              const SizedBox(height: ItangoSpacing.s6),
              if (qrCode == null)
                const Padding(
                  padding: EdgeInsets.all(ItangoSpacing.s6),
                  child: Text(
                    "No ticket QR found for this event. If you just purchased a ticket, this can take a moment to appear — pull to refresh from the event page.",
                    style: TextStyle(color: ItangoColors.statusDanger),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(ItangoSpacing.s5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ItangoRadius.xl)),
                  child: QrImageView(
                    data: qrCode,
                    version: QrVersions.auto,
                    size: 240,
                    // Error-correction is set to high (not the qr_flutter
                    // default) since this code will be scanned off a phone
                    // screen under variable club lighting, not printed on
                    // paper under controlled conditions — more redundancy
                    // means more successful scans on the first try.
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                  ),
                ),
              const SizedBox(height: ItangoSpacing.s6),
              Container(
                padding: const EdgeInsets.all(ItangoSpacing.s4),
                decoration: BoxDecoration(color: ItangoColors.bgSurface, borderRadius: BorderRadius.circular(ItangoRadius.lg)),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: ItangoColors.accentCyan, size: 18),
                    SizedBox(width: ItangoSpacing.s2),
                    Expanded(
                      child: Text(
                        "No scanner at the door? You can also check yourself in from the event page using your location.",
                        style: TextStyle(color: ItangoColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
