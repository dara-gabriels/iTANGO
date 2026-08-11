// test/features/events/purchase_controller_test.dart
//
// NOTE on scope: this file tests PurchaseController only. CheckInController
// is NOT unit-tested here — it calls Geolocator.getCurrentPosition()
// directly, which hits a platform channel that needs geolocator's own
// testing shims (setting a mock platform implementation) to drive in a
// pure unit test. Writing tests that don't actually exercise that call
// (e.g. only testing the response-mapping logic after the fact) would
// produce tests that always pass without testing the thing that most
// often breaks in practice — location permission/service state. This is
// tracked as a real gap in test/README.md rather than papered over with
// tests that assert nothing meaningful.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:itango/core/supabase/supabase_providers.dart';
import 'package:itango/features/events/domain/event_detail_models.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late ProviderContainer container;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);

    container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(mockClient)],
    );
  });

  tearDown(() => container.dispose());

  group('PurchaseController', () {
    test('transitions to NeedsRedirect when the response includes a payment_redirect_url', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => FunctionResponse(
          status: 201,
          data: {
            'ticket_purchase_id': 'purchase-1',
            'status': 'pending',
            'payment_redirect_url': 'https://checkout.paystack.com/abc123',
            'qr_code': 'signed-token',
          },
        ),
      );

      final controller = container.read(purchaseControllerProvider.notifier);
      await controller.purchase(ticketId: 'ticket-1', quantity: 1, paymentProvider: 'paystack');

      final state = container.read(purchaseControllerProvider);
      expect(state, isA<PurchaseNeedsRedirect>());
      expect((state as PurchaseNeedsRedirect).url, 'https://checkout.paystack.com/abc123');
    });

    test('transitions to Succeeded (no redirect) for a wallet payment that settles synchronously', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => FunctionResponse(
          status: 201,
          data: {
            'ticket_purchase_id': 'purchase-2',
            'status': 'paid',
            'payment_redirect_url': null,
            'qr_code': 'signed-token',
          },
        ),
      );

      final controller = container.read(purchaseControllerProvider.notifier);
      await controller.purchase(ticketId: 'ticket-1', quantity: 1, paymentProvider: 'wallet');

      expect(container.read(purchaseControllerProvider), isA<PurchaseSucceeded>());
    });

    test('transitions to Failed with the server-provided message on a non-201 response', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => FunctionResponse(
          status: 409,
          data: {'message': 'Only 2 of this ticket type remain'},
        ),
      );

      final controller = container.read(purchaseControllerProvider.notifier);
      await controller.purchase(ticketId: 'ticket-1', quantity: 5, paymentProvider: 'paystack');

      final state = container.read(purchaseControllerProvider);
      expect(state, isA<PurchaseFailed>());
      expect((state as PurchaseFailed).message, 'Only 2 of this ticket type remain');
    });

    test('transitions to Failed with a generic message when the network call throws', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body'))).thenThrow(Exception('network error'));

      final controller = container.read(purchaseControllerProvider.notifier);
      await controller.purchase(ticketId: 'ticket-1', quantity: 1, paymentProvider: 'paystack');

      expect(container.read(purchaseControllerProvider), isA<PurchaseFailed>());
    });
  });
}
