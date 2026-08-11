// lib/features/profile/domain/profile_models.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';

class ProfilePassport {
  ProfilePassport({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.coverUrl,
    required this.bio,
    required this.isVerified,
    required this.energyScore,
    required this.energyScorePercentile,
    required this.currentlyAtEventTitle,
    required this.eventCount,
    required this.friendCount,
    required this.walletBalance,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? coverUrl;
  final String? bio;
  final bool isVerified;
  final int energyScore;
  final double? energyScorePercentile; // e.g. 95.0 = "Top 5% this month"
  final String? currentlyAtEventTitle;
  final int eventCount;
  final int friendCount;
  final double walletBalance;

  bool get isTopFivePercent => (energyScorePercentile ?? 0) >= 95;
}

final profilePassportProvider = FutureProvider.autoDispose<ProfilePassport>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final profileRow = await client
      .from('profiles')
      .select('''
        id, username, display_name, avatar_url, cover_url, bio, is_verified,
        energy_score, energy_score_percentile,
        events:currently_at_event_id ( title ),
        wallets ( balance )
      ''')
      .eq('id', userId)
      .single();

  final checkInCountResponse = await client
      .from('check_ins')
      .select('id')
      .eq('user_id', userId)
      .count();

  final friendCountResponse = await client
      .from('friendships')
      .select('user_id')
      .eq('status', 'accepted')
      .or('user_id.eq.$userId,friend_id.eq.$userId')
      .count();

  final currentEvent = profileRow['events'] as Map<String, dynamic>?;
  final wallet = profileRow['wallets'] as Map<String, dynamic>?;

  return ProfilePassport(
    userId: profileRow['id'] as String,
    username: profileRow['username'] as String,
    displayName: profileRow['display_name'] as String,
    avatarUrl: profileRow['avatar_url'] as String?,
    coverUrl: profileRow['cover_url'] as String?,
    bio: profileRow['bio'] as String?,
    isVerified: profileRow['is_verified'] as bool? ?? false,
    energyScore: profileRow['energy_score'] as int,
    energyScorePercentile: (profileRow['energy_score_percentile'] as num?)?.toDouble(),
    currentlyAtEventTitle: currentEvent?['title'] as String?,
    eventCount: checkInCountResponse.count,
    friendCount: friendCountResponse.count,
    walletBalance: (wallet?['balance'] as num?)?.toDouble() ?? 0,
  );
});

class VoucherCard {
  VoucherCard({
    required this.redemptionId,
    required this.title,
    required this.value,
    required this.currency,
    required this.expiresAt,
    required this.status,
  });

  final String redemptionId;
  final String title;
  final double value;
  final String currency;
  final DateTime expiresAt;
  final String status; // claimed | redeemed | expired
}

final myVouchersProvider = FutureProvider.autoDispose<List<VoucherCard>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final rows = await client
      .from('voucher_redemptions')
      .select('id, status, vouchers ( title, value, currency, expires_at )')
      .eq('user_id', userId)
      .eq('status', 'claimed')
      .order('claimed_at', ascending: false);

  return (rows as List).map((row) {
    final voucher = row['vouchers'] as Map<String, dynamic>;
    return VoucherCard(
      redemptionId: row['id'] as String,
      title: voucher['title'] as String,
      value: (voucher['value'] as num).toDouble(),
      currency: voucher['currency'] as String,
      expiresAt: DateTime.parse(voucher['expires_at'] as String),
      status: row['status'] as String,
    );
  }).toList();
});

class EarnedAchievement {
  EarnedAchievement({required this.code, required this.name, required this.icon, required this.earnedAt});
  final String code;
  final String name;
  final String? icon;
  final DateTime earnedAt;
}

final myAchievementsProvider = FutureProvider.autoDispose<List<EarnedAchievement>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final rows = await client
      .from('user_achievements')
      .select('earned_at, achievements ( code, name, icon )')
      .eq('user_id', userId)
      .order('earned_at', ascending: false);

  return (rows as List).map((row) {
    final achievement = row['achievements'] as Map<String, dynamic>;
    return EarnedAchievement(
      code: achievement['code'] as String,
      name: achievement['name'] as String,
      icon: achievement['icon'] as String?,
      earnedAt: DateTime.parse(row['earned_at'] as String),
    );
  }).toList();
});
