// lib/features/events/domain/event_detail_models.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/supabase/supabase_providers.dart';

class TicketOption {
  TicketOption({
    required this.id,
    required this.name,
    required this.ticketType,
    required this.price,
    required this.currency,
    required this.quantityTotal,
    required this.quantitySold,
  });

  final String id;
  final String name;
  final String ticketType;
  final double price;
  final String currency;
  final int quantityTotal;
  final int quantitySold;

  int get remaining => quantityTotal - quantitySold;
  bool get isSoldOut => remaining <= 0;

  factory TicketOption.fromRow(Map<String, dynamic> row) => TicketOption(
        id: row['id'] as String,
        name: row['name'] as String,
        ticketType: row['ticket_type'] as String,
        price: (row['price'] as num).toDouble(),
        currency: row['currency'] as String,
        quantityTotal: row['quantity_total'] as int,
        quantitySold: row['quantity_sold'] as int,
      );
}

class EventDetail {
  EventDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.startTime,
    required this.venueName,
    required this.venueCity,
    required this.venueLat,
    required this.venueLng,
    required this.liveAttendeeCount,
    required this.status,
    required this.tickets,
    required this.userHasCheckedIn,
    required this.userTicketPurchaseId,
    required this.userTicketQrCode,
  });

  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final DateTime startTime;
  final String? venueName;
  final String? venueCity;
  final double? venueLat;
  final double? venueLng;
  final int liveAttendeeCount;
  final String status;
  final List<TicketOption> tickets;
  final bool userHasCheckedIn;
  final String? userTicketPurchaseId;
  final String? userTicketQrCode;

  bool get hasValidTicket => userTicketPurchaseId != null;
}

final eventDetailProvider = FutureProvider.autoDispose.family<EventDetail, String>((ref, eventId) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final eventRow = await client
      .from('events')
      .select('''
        id, title, description, cover_url, start_time, status, live_attendee_count,
        venues ( name, city, location ),
        tickets ( id, name, ticket_type, price, currency, quantity_total, quantity_sold )
      ''')
      .eq('id', eventId)
      .single();

  final checkInRow = await client
      .from('check_ins')
      .select('id')
      .eq('event_id', eventId)
      .eq('user_id', userId)
      .maybeSingle();

  final ticketPurchaseRow = await client
      .from('ticket_purchases')
      .select('id, qr_code, tickets!inner(event_id)')
      .eq('user_id', userId)
      .eq('status', 'paid')
      .eq('tickets.event_id', eventId)
      .maybeSingle();

  final venue = eventRow['venues'] as Map<String, dynamic>?;
  final venueLocation = venue?['location'] as Map<String, dynamic>?; // GeoJSON via PostgREST
  final ticketsRaw = (eventRow['tickets'] as List?) ?? [];

  return EventDetail(
    id: eventRow['id'] as String,
    title: eventRow['title'] as String,
    description: eventRow['description'] as String?,
    coverUrl: eventRow['cover_url'] as String?,
    startTime: DateTime.parse(eventRow['start_time'] as String),
    venueName: venue?['name'] as String?,
    venueCity: venue?['city'] as String?,
    venueLat: venueLocation != null ? (venueLocation['coordinates'][1] as num).toDouble() : null,
    venueLng: venueLocation != null ? (venueLocation['coordinates'][0] as num).toDouble() : null,
    liveAttendeeCount: eventRow['live_attendee_count'] as int,
    status: eventRow['status'] as String,
    tickets: ticketsRaw.map((t) => TicketOption.fromRow(t as Map<String, dynamic>)).toList(),
    userHasCheckedIn: checkInRow != null,
    userTicketPurchaseId: ticketPurchaseRow?['id'] as String?,
    userTicketQrCode: ticketPurchaseRow?['qr_code'] as String?,
  );
});

// -----------------------------------------------------------------------------
// Ticket purchase
// -----------------------------------------------------------------------------
sealed class PurchaseState {
  const PurchaseState();
}
class PurchaseIdle extends PurchaseState { const PurchaseIdle(); }
class PurchaseSubmitting extends PurchaseState { const PurchaseSubmitting(); }
class PurchaseNeedsRedirect extends PurchaseState {
  const PurchaseNeedsRedirect(this.url);
  final String url;
}
class PurchaseSucceeded extends PurchaseState { const PurchaseSucceeded(); }
class PurchaseFailed extends PurchaseState {
  const PurchaseFailed(this.message);
  final String message;
}

class PurchaseController extends StateNotifier<PurchaseState> {
  PurchaseController(this._ref) : super(const PurchaseIdle());
  final Ref _ref;

  Future<void> purchase({
    required String ticketId,
    required int quantity,
    required String paymentProvider,
  }) async {
    state = const PurchaseSubmitting();
    final client = _ref.read(supabaseClientProvider);

    try {
      final response = await client.functions.invoke('tickets-purchase', body: {
        'ticket_id': ticketId,
        'quantity': quantity,
        'payment_provider': paymentProvider,
      });

      if (response.status != 201) {
        final message = (response.data is Map) ? response.data['message'] as String? : null;
        state = PurchaseFailed(message ?? 'Purchase failed — please try again.');
        return;
      }

      final data = response.data as Map<String, dynamic>;
      final redirectUrl = data['payment_redirect_url'] as String?;

      if (redirectUrl != null) {
        state = PurchaseNeedsRedirect(redirectUrl);
      } else {
        // Wallet payments settle synchronously — status is already 'paid'.
        state = const PurchaseSucceeded();
      }
    } catch (e) {
      state = PurchaseFailed('Something went wrong. Please try again.');
    }
  }

  void reset() => state = const PurchaseIdle();
}

final purchaseControllerProvider = StateNotifierProvider.autoDispose<PurchaseController, PurchaseState>((ref) {
  return PurchaseController(ref);
});

// -----------------------------------------------------------------------------
// Check-in (geofence self-check-in — see events/presentation/check_in_screen.dart
// for why geofence, not QR, is the primary consumer-app flow)
// -----------------------------------------------------------------------------
sealed class CheckInState {
  const CheckInState();
}
class CheckInIdle extends CheckInState { const CheckInIdle(); }
class CheckInSubmitting extends CheckInState { const CheckInSubmitting(); }
class CheckInSucceeded extends CheckInState {
  const CheckInSucceeded({required this.energyAwarded, required this.chatRoomConversationId});
  final int energyAwarded;
  final String? chatRoomConversationId;
}
class CheckInFailed extends CheckInState {
  const CheckInFailed(this.message);
  final String message;
}

class CheckInController extends StateNotifier<CheckInState> {
  CheckInController(this._ref) : super(const CheckInIdle());
  final Ref _ref;

  Future<void> checkIn(String eventId) async {
    state = const CheckInSubmitting();
    final client = _ref.read(supabaseClientProvider);

    try {
      final position = await Geolocator.getCurrentPosition();
      final response = await client.functions.invoke('checkins', body: {
        'event_id': eventId,
        'method': 'geofence',
        'location': {'lat': position.latitude, 'lng': position.longitude},
      });

      if (response.status != 201) {
        final message = (response.data is Map) ? response.data['message'] as String? : null;
        state = CheckInFailed(message ?? "Couldn't check you in — try again.");
        return;
      }

      final data = response.data as Map<String, dynamic>;
      state = CheckInSucceeded(
        energyAwarded: data['energy_awarded'] as int? ?? 0,
        chatRoomConversationId: data['chat_room_conversation_id'] as String?,
      );
    } catch (e) {
      state = CheckInFailed("Couldn't verify your location. Make sure location services are on.");
    }
  }
}

final checkInControllerProvider = StateNotifierProvider.autoDispose<CheckInController, CheckInState>((ref) {
  return CheckInController(ref);
});
