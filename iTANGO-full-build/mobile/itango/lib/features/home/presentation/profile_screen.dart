// lib/features/home/presentation/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/itango_theme.dart';
import '../../profile/domain/profile_models.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passport = ref.watch(profilePassportProvider);

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      body: passport.when(
        loading: () => const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary)),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(ItangoSpacing.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't load your profile.", style: TextStyle(color: ItangoColors.textPrimary)),
                const SizedBox(height: ItangoSpacing.s3),
                TextButton(
                  onPressed: () => ref.invalidate(profilePassportProvider),
                  child: const Text('Retry', style: TextStyle(color: ItangoColors.brandPrimary)),
                ),
              ],
            ),
          ),
        ),
        data: (p) => RefreshIndicator(
          color: ItangoColors.brandPrimary,
          onRefresh: () async {
            ref.invalidate(profilePassportProvider);
            ref.invalidate(myVouchersProvider);
            ref.invalidate(myAchievementsProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: ItangoColors.bgBase,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      p.coverUrl != null
                          ? Image.network(p.coverUrl!, fit: BoxFit.cover)
                          : Container(color: ItangoColors.bgSurfaceElevated),
                      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ))),
                      Positioned(
                        top: ItangoSpacing.s12,
                        left: ItangoSpacing.s4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s3, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(ItangoRadius.pill)),
                          child: const Text('My Passport', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(ItangoSpacing.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: ItangoColors.bgSurfaceElevated,
                            backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
                          ),
                          const SizedBox(width: ItangoSpacing.s3),
                          _EnergyBadge(score: p.energyScore, isTopFivePercent: p.isTopFivePercent),
                        ],
                      ),
                      const SizedBox(height: ItangoSpacing.s3),
                      Row(
                        children: [
                          Text(p.displayName, style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 22, fontWeight: FontWeight.w700, color: ItangoColors.textPrimary)),
                          if (p.isVerified) ...[
                            const SizedBox(width: ItangoSpacing.s1),
                            const Icon(Icons.verified, color: ItangoColors.accentCyan, size: 18),
                          ],
                        ],
                      ),
                      Text('@${p.username}', style: const TextStyle(color: ItangoColors.textSecondary)),
                      if (p.bio != null) ...[
                        const SizedBox(height: ItangoSpacing.s2),
                        Text(p.bio!, style: const TextStyle(color: ItangoColors.textPrimary)),
                      ],
                      if (p.currentlyAtEventTitle != null) ...[
                        const SizedBox(height: ItangoSpacing.s2),
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: ItangoColors.accentEmerald, size: 14),
                            const SizedBox(width: 4),
                            Text('Currently at ${p.currentlyAtEventTitle}', style: const TextStyle(color: ItangoColors.accentEmerald, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                      const SizedBox(height: ItangoSpacing.s5),
                      Row(
                        children: [
                          _StatColumn(label: 'Events', value: '${p.eventCount}'),
                          _StatColumn(label: 'Friends', value: '${p.friendCount}'),
                          _StatColumn(label: 'Energy', value: '${p.energyScore}'),
                        ],
                      ),
                      const SizedBox(height: ItangoSpacing.s6),
                      _VoucherWalletSection(balance: p.walletBalance),
                      const SizedBox(height: ItangoSpacing.s6),
                      const _AchievementsSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnergyBadge extends StatelessWidget {
  const _EnergyBadge({required this.score, required this.isTopFivePercent});
  final int score;
  final bool isTopFivePercent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s3, vertical: ItangoSpacing.s2),
          decoration: BoxDecoration(gradient: ItangoGradients.primaryCta, borderRadius: BorderRadius.circular(ItangoRadius.md)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text('Energy Score  $score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (isTopFivePercent) ...[
          const SizedBox(height: 4),
          const Text('⭐ Top 5% this month', style: TextStyle(color: ItangoColors.accentAmber, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: ItangoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: ItangoColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _VoucherWalletSection extends ConsumerWidget {
  const _VoucherWalletSection({required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(myVouchersProvider);
    final currencyFormat = NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Voucher Wallet', style: TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            Text(currencyFormat.format(balance), style: const TextStyle(color: ItangoColors.accentAmber, fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        const SizedBox(height: ItangoSpacing.s3),
        vouchers.when(
          loading: () => const LinearProgressIndicator(color: ItangoColors.brandPrimary),
          error: (_, __) => const Text('Could not load vouchers', style: TextStyle(color: ItangoColors.textSecondary)),
          data: (list) => list.isEmpty
              ? const Text('No active vouchers — check in at more events to earn perks.', style: TextStyle(color: ItangoColors.textSecondary, fontSize: 13))
              : SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: ItangoSpacing.s3),
                    itemBuilder: (_, i) {
                      final v = list[i];
                      return Container(
                        width: 160,
                        padding: const EdgeInsets.all(ItangoSpacing.s3),
                        decoration: BoxDecoration(
                          gradient: ItangoGradients.primaryCta,
                          borderRadius: BorderRadius.circular(ItangoRadius.md),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(v.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text('Expires ${DateFormat.MMMd().format(v.expiresAt)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _AchievementsSection extends ConsumerWidget {
  const _AchievementsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(myAchievementsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Achievements', style: TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: ItangoSpacing.s3),
        achievements.when(
          loading: () => const LinearProgressIndicator(color: ItangoColors.brandPrimary),
          error: (_, __) => const Text('Could not load achievements', style: TextStyle(color: ItangoColors.textSecondary)),
          data: (list) => list.isEmpty
              ? const Text('Attend events and stay active to earn your first badge.', style: TextStyle(color: ItangoColors.textSecondary, fontSize: 13))
              : Wrap(
                  spacing: ItangoSpacing.s3,
                  runSpacing: ItangoSpacing.s3,
                  children: list.map((a) => _AchievementChip(achievement: a)).toList(),
                ),
        ),
      ],
    );
  }
}

class _AchievementChip extends StatelessWidget {
  const _AchievementChip({required this.achievement});
  final EarnedAchievement achievement;

  IconData get _icon => switch (achievement.icon) {
        'flame' => Icons.local_fire_department_rounded,
        'star' => Icons.star_rounded,
        'people' => Icons.people_alt_rounded,
        _ => Icons.emoji_events_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.all(ItangoSpacing.s3),
      decoration: BoxDecoration(color: ItangoColors.bgSurface, borderRadius: BorderRadius.circular(ItangoRadius.md)),
      child: Column(
        children: [
          Icon(_icon, color: ItangoColors.accentAmber, size: 24),
          const SizedBox(height: 6),
          Text(achievement.name, style: const TextStyle(color: ItangoColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
