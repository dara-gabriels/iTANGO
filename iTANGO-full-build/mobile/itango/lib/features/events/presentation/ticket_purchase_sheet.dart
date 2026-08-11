// lib/features/events/presentation/ticket_purchase_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/itango_theme.dart';
import '../domain/event_detail_models.dart';

class TicketPurchaseSheet extends ConsumerStatefulWidget {
  const TicketPurchaseSheet({super.key, required this.eventId, required this.tickets});
  final String eventId;
  final List<TicketOption> tickets;

  @override
  ConsumerState<TicketPurchaseSheet> createState() => _TicketPurchaseSheetState();
}

class _TicketPurchaseSheetState extends ConsumerState<TicketPurchaseSheet> {
  late TicketOption _selectedTicket;
  int _quantity = 1;
  String _paymentProvider = 'wallet';

  @override
  void initState() {
    super.initState();
    _selectedTicket = widget.tickets.firstWhere((t) => !t.isSoldOut, orElse: () => widget.tickets.first);
  }

  double get _total => _selectedTicket.price * _quantity;

  @override
  Widget build(BuildContext context) {
    final purchaseState = ref.watch(purchaseControllerProvider);

    ref.listen(purchaseControllerProvider, (previous, next) async {
      if (next is PurchaseNeedsRedirect) {
        final uri = Uri.parse(next.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        // The purchase confirms asynchronously via the PSP webhook (Phase 5);
        // the client can't know the outcome until it re-fetches event
        // detail after returning from the browser. We close the sheet here
        // and let the caller's `.then()` (event_detail_screen.dart) refresh.
        if (context.mounted) Navigator.of(context).pop();
      } else if (next is PurchaseSucceeded) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ticket purchased!'), backgroundColor: ItangoColors.statusSuccess),
          );
          Navigator.of(context).pop();
        }
      } else if (next is PurchaseFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message), backgroundColor: ItangoColors.statusDanger),
        );
      }
    });

    final isSubmitting = purchaseState is PurchaseSubmitting;

    return Padding(
      padding: EdgeInsets.only(
        left: ItangoSpacing.s5, right: ItangoSpacing.s5, top: ItangoSpacing.s5,
        bottom: MediaQuery.of(context).viewInsets.bottom + ItangoSpacing.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Get Tickets', style: TextStyle(color: ItangoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: ItangoSpacing.s4),
          for (final ticket in widget.tickets) _TicketRadioTile(
            ticket: ticket,
            selected: _selectedTicket.id == ticket.id,
            onTap: ticket.isSoldOut ? null : () => setState(() => _selectedTicket = ticket),
          ),
          const SizedBox(height: ItangoSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Quantity', style: TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  IconButton(
                    onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    icon: const Icon(Icons.remove_circle_outline, color: ItangoColors.textSecondary),
                  ),
                  Text('$_quantity', style: const TextStyle(color: ItangoColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                  IconButton(
                    onPressed: _quantity < _selectedTicket.remaining ? () => setState(() => _quantity++) : null,
                    icon: const Icon(Icons.add_circle_outline, color: ItangoColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: ItangoSpacing.s4),
          const Text('Pay with', style: TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: ItangoSpacing.s2),
          Wrap(
            spacing: ItangoSpacing.s2,
            children: [
              _PaymentChip(label: 'Wallet', value: 'wallet', groupValue: _paymentProvider, onSelected: (v) => setState(() => _paymentProvider = v)),
              _PaymentChip(label: 'Paystack', value: 'paystack', groupValue: _paymentProvider, onSelected: (v) => setState(() => _paymentProvider = v)),
            ],
          ),
          const SizedBox(height: ItangoSpacing.s5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(color: ItangoColors.textSecondary)),
              Text('${_selectedTicket.currency} ${_total.toStringAsFixed(0)}', style: const TextStyle(color: ItangoColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: ItangoSpacing.s4),
          isSubmitting
              ? const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary))
              : ItangoGradientButton(
                  label: 'Confirm Purchase',
                  onPressed: () => ref.read(purchaseControllerProvider.notifier).purchase(
                        ticketId: _selectedTicket.id,
                        quantity: _quantity,
                        paymentProvider: _paymentProvider,
                      ),
                ),
        ],
      ),
    );
  }
}

class _TicketRadioTile extends StatelessWidget {
  const _TicketRadioTile({required this.ticket, required this.selected, required this.onTap});
  final TicketOption ticket;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: ticket.isSoldOut ? 0.4 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ItangoRadius.md),
        child: Container(
          margin: const EdgeInsets.only(bottom: ItangoSpacing.s2),
          padding: const EdgeInsets.all(ItangoSpacing.s3),
          decoration: BoxDecoration(
            color: selected ? ItangoColors.brandPrimary.withOpacity(0.12) : ItangoColors.bgSurfaceElevated,
            borderRadius: BorderRadius.circular(ItangoRadius.md),
            border: Border.all(color: selected ? ItangoColors.brandPrimary : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? ItangoColors.brandPrimary : ItangoColors.textTertiary, size: 20),
              const SizedBox(width: ItangoSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticket.name, style: const TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600)),
                    Text(
                      ticket.isSoldOut ? 'Sold out' : '${ticket.remaining} remaining',
                      style: TextStyle(color: ticket.isSoldOut ? ItangoColors.statusDanger : ItangoColors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text('${ticket.currency} ${ticket.price.toStringAsFixed(0)}', style: const TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({required this.label, required this.value, required this.groupValue, required this.onSelected});
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s2),
        decoration: BoxDecoration(
          gradient: selected ? ItangoGradients.primaryCta : null,
          color: selected ? null : ItangoColors.bgSurfaceElevated,
          borderRadius: BorderRadius.circular(ItangoRadius.pill),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : ItangoColors.textSecondary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
