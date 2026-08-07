import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/constants.dart';

class MyReviewsScreen extends StatefulWidget {
  final String userId;

  const MyReviewsScreen({super.key, required this.userId});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final FirestoreService _firestore = FirestoreService();
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    developer.log('_loadReviews: userId=${widget.userId}', name: 'MyReviews');
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final reviews = await _firestore.fetchUserReviews(widget.userId);
      developer.log('_loadReviews: got ${reviews.length} reviews', name: 'MyReviews');

      if (reviews.isEmpty) {
        // No reviews in userReviews — try migration for existing data
        developer.log('_loadReviews: empty — running migration...', name: 'MyReviews');
        final migrated = await _firestore.migrateExistingReviews(widget.userId);
        developer.log('_loadReviews: migrated $migrated reviews', name: 'MyReviews');

        // Re-query after migration
        final retryReviews = await _firestore.fetchUserReviews(widget.userId);
        developer.log('_loadReviews: after migration: ${retryReviews.length} reviews', name: 'MyReviews');

        if (!mounted) return;
        setState(() {
          _reviews = retryReviews;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _reviews = reviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      developer.log('fetchUserReviews failed: $e', name: 'MyReviews');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _reviews = [];
        _hasError = true;
      });
    }
  }

  String _relativeTime(dynamic timestamp) {
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return '';
    }

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    }
    final years = (diff.inDays / 365).floor();
    return '$years year${years > 1 ? 's' : ''} ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('My Reviews'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_reviews.length} Review${_reviews.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_hasError) return _buildErrorState(theme);
    if (_isLoading) return _buildLoadingState(theme);
    if (_reviews.isEmpty) return _buildEmptyState(theme);
    return _buildReviewList(theme);
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Unable to load reviews.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadReviews,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (_, i) => _buildSkeletonCard(theme),
    );
  }

  Widget _buildSkeletonCard(ThemeData theme) {
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 14, color: baseColor),
                    const SizedBox(height: 6),
                    Container(width: 80, height: 12, color: baseColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              5,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(width: 18, height: 18, color: baseColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rate_review_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Reviews Yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "You haven't submitted any community reviews yet.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.explore_outlined, size: 20),
              label: const Text('Explore Places'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _reviews.length,
      itemBuilder: (context, index) {
        final entry = _reviews[index];
        final review = entry['review'] as Map<String, dynamic>;
        final placeName = entry['placeName'] as String;
        final reviewType = entry['reviewType'] as String? ?? 'place';
        return _buildReviewCard(theme, review, placeName, reviewType);
      },
    );
  }

  Widget _buildReviewCard(ThemeData theme, Map<String, dynamic> review, String placeName, String reviewType) {
    final overallSafety = review['overallSafety'] as int? ?? 0;
    final timeOfDay = review['timeOfDay'] as String?;
    final lighting = review['lighting'] as String?;
    final crowd = review['crowd'] as String?;
    final policePresence = review['policePresence'] as String?;
    final walkingAlone = review['walkingAlone'] as String?;
    final comment = review['comment'] as String?;
    final createdAt = review['createdAt'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    reviewType == 'road' ? Icons.route : Icons.place_outlined,
                    size: 20,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placeName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _relativeTime(createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ...List.generate(5, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      i < overallSafety
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 20,
                      color: i < overallSafety
                          ? const Color(0xFFF59E0B)
                          : theme.colorScheme.outlineVariant,
                    ),
                  );
                }),
                const SizedBox(width: 6),
                Text(
                  'Overall Safety',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (timeOfDay != null)
                  _chip(theme, Icons.access_time, timeOfDay, _getTimeColor(timeOfDay)),
                if (lighting != null)
                  _chip(theme, Icons.light_mode, '$lighting Lighting', _getLightingColor(lighting)),
                if (crowd != null)
                  _chip(theme, Icons.people, crowd, _getCrowdColor(crowd)),
                if (policePresence != null)
                  _chip(theme, Icons.local_police, policePresence, _getPoliceColor(policePresence)),
                if (walkingAlone != null)
                  _chip(theme, Icons.directions_walk, 'Walk: $walkingAlone', _getWalkColor(walkingAlone)),
              ],
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  comment,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTimeColor(String time) {
    switch (time) {
      case 'Morning': return const Color(0xFFF59E0B);
      case 'Afternoon': return const Color(0xFFEF6C00);
      case 'Evening': return const Color(0xFF7C3AED);
      case 'Night': return const Color(0xFF1E40AF);
      default: return const Color(0xFF6B7280);
    }
  }

  Color _getLightingColor(String lighting) {
    switch (lighting) {
      case 'Good': return const Color(0xFF16A34A);
      case 'Average': return const Color(0xFFF59E0B);
      case 'Poor': return const Color(0xFFDC2626);
      default: return const Color(0xFF6B7280);
    }
  }

  Color _getCrowdColor(String crowd) {
    switch (crowd) {
      case 'Busy': return const Color(0xFF2563EB);
      case 'Moderate': return const Color(0xFF7C3AED);
      case 'Isolated': return const Color(0xFFDC2626);
      default: return const Color(0xFF6B7280);
    }
  }

  Color _getPoliceColor(String police) {
    switch (police) {
      case 'Frequent': return const Color(0xFF16A34A);
      case 'Occasional': return const Color(0xFFF59E0B);
      case 'None': return const Color(0xFFDC2626);
      default: return const Color(0xFF6B7280);
    }
  }

  Color _getWalkColor(String walk) {
    switch (walk) {
      case 'Yes': return const Color(0xFF16A34A);
      case 'Maybe': return const Color(0xFFF59E0B);
      case 'No': return const Color(0xFFDC2626);
      default: return const Color(0xFF6B7280);
    }
  }
}
