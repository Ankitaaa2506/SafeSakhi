import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app.dart';
import '../screens/review_form_screen.dart';
import '../services/firestore_service.dart';

class CommunityReviewsScreen extends StatefulWidget {
  final String targetId;
  final String targetName;
  final bool isRoad;
  final double? latitude;
  final double? longitude;

  const CommunityReviewsScreen({
    super.key,
    required this.targetId,
    required this.targetName,
    required this.isRoad,
    this.latitude,
    this.longitude,
  });

  @override
  State<CommunityReviewsScreen> createState() => _CommunityReviewsScreenState();
}

class _CommunityReviewsScreenState extends State<CommunityReviewsScreen> with RouteAware {
  final FirestoreService _firestore = FirestoreService();
  final List<DocumentSnapshot> _reviews = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadInitialReviews();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadInitialReviews();
  }

  Future<void> _loadInitialReviews() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final snapshot = widget.isRoad
          ? await _firestore.fetchRoadReviews(widget.targetId, limit: _pageSize)
          : await _firestore.fetchPlaceReviews(widget.targetId, limit: _pageSize);

      if (!mounted) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(snapshot.docs);
        _hasMore = snapshot.docs.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _loadMoreReviews() async {
    if (!_hasMore || _isLoadingMore || _reviews.isEmpty) return;

    setState(() => _isLoadingMore = true);

    try {
      final lastDoc = _reviews.last;
      final snapshot = widget.isRoad
          ? await _firestore.fetchRoadReviews(
              widget.targetId,
              limit: _pageSize,
              lastDoc: lastDoc,
            )
          : await _firestore.fetchPlaceReviews(
              widget.targetId,
              limit: _pageSize,
              lastDoc: lastDoc,
            );

      if (!mounted) return;
      setState(() {
        _reviews.addAll(snapshot.docs);
        _hasMore = snapshot.docs.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
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
        title: const Text('Community Reviews'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_reviews.length} Reviews',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.filter_list_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onSelected: (value) {},
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'newest',
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Newest'),
                    const Spacer(),
                    Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'highest',
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(width: 8),
                    Text('Highest Rated', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3))),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'lowest',
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(width: 8),
                    Text('Lowest Rated', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3))),
                  ],
                ),
              ),
            ],
          ),
        ],
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
              onPressed: _loadInitialReviews,
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
      itemCount: 5,
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
              _skeletonCircle(theme, 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonLine(theme, 100, 14, baseColor),
                    const SizedBox(height: 6),
                    _skeletonLine(theme, 60, 12, baseColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _skeletonLine(theme, 120, 16, baseColor),
          const SizedBox(height: 12),
          Row(
            children: [
              _skeletonChip(theme, baseColor),
              const SizedBox(width: 8),
              _skeletonChip(theme, baseColor),
              const SizedBox(width: 8),
              _skeletonChip(theme, baseColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skeletonCircle(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _skeletonLine(ThemeData theme, double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _skeletonChip(ThemeData theme, Color color) {
    return Container(
      width: 60,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
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
                Icons.reviews_rounded,
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
              'Be the first person to help the community\nby sharing your experience.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReviewFormScreen(
                      targetId: widget.targetId,
                      targetName: widget.targetName,
                      targetType: widget.isRoad
                          ? ReviewTargetType.road
                          : ReviewTargetType.place,
                      latitude: widget.latitude,
                      longitude: widget.longitude,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: const Text('Write First Review'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadInitialReviews,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverList.separated(
              itemCount: _reviews.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == _reviews.length) {
                  _loadMoreReviews();
                  return _buildLoadingCard(theme);
                }
                final data = _reviews[index].data() as Map<String, dynamic>;
                return _buildReviewCard(theme, data);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildReviewCard(ThemeData theme, Map<String, dynamic> data) {
    final userName = data['userName'] as String? ?? 'Anonymous';
    final userPhotoUrl = data['userPhotoUrl'] as String?;
    final overallSafety = data['overallSafety'] as int? ?? 0;
    final timeOfDay = data['timeOfDay'] as String?;
    final lighting = data['lighting'] as String?;
    final crowd = data['crowd'] as String?;
    final policePresence = data['policePresence'] as String?;
    final walkingAlone = data['walkingAlone'] as String?;
    final comment = data['comment'] as String?;
    final createdAt = data['createdAt'];

    return Container(
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
            _buildHeader(theme, userName, userPhotoUrl, createdAt),
            const SizedBox(height: 12),
            _buildRating(theme, overallSafety),
            const SizedBox(height: 12),
            _buildChips(theme, timeOfDay, lighting, crowd, policePresence, walkingAlone),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildComment(theme, comment),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String userName, String? userPhotoUrl, dynamic createdAt) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: userPhotoUrl != null && userPhotoUrl.isNotEmpty
              ? NetworkImage(userPhotoUrl)
              : null,
          child: userPhotoUrl == null || userPhotoUrl.isEmpty
              ? Text(
                  userName[0].toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
    );
  }

  Widget _buildRating(ThemeData theme, int overallSafety) {
    return Row(
      children: [
        ...List.generate(5, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              i < overallSafety
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 22,
              color: i < overallSafety
                  ? const Color(0xFFF59E0B)
                  : theme.colorScheme.outlineVariant,
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          'Overall Safety',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildChips(
    ThemeData theme,
    String? timeOfDay,
    String? lighting,
    String? crowd,
    String? policePresence,
    String? walkingAlone,
  ) {
    final chips = <_ChipData>[];

    if (timeOfDay != null) {
      final icon = timeOfDay == 'Night'
          ? Icons.nightlight_round
          : timeOfDay == 'Morning'
              ? Icons.wb_sunny_rounded
              : timeOfDay == 'Afternoon'
                  ? Icons.wb_cloudy_rounded
                  : Icons.wb_twilight_rounded;
      chips.add(_ChipData(icon, timeOfDay, _getTimeColor(timeOfDay)));
    }

    if (lighting != null) {
      final icon = lighting == 'Good'
          ? Icons.light_mode_rounded
          : lighting == 'Average'
              ? Icons.lightbulb_outline_rounded
              : Icons.dark_mode_rounded;
      chips.add(_ChipData(icon, '$lighting Lighting', _getLightingColor(lighting)));
    }

    if (crowd != null) {
      final icon = crowd == 'Busy'
          ? Icons.groups_rounded
          : crowd == 'Moderate'
              ? Icons.person_rounded
              : Icons.person_off_rounded;
      chips.add(_ChipData(icon, crowd, _getCrowdColor(crowd)));
    }

    if (policePresence != null) {
      final icon = policePresence == 'Frequent'
          ? Icons.local_police_rounded
          : Icons.shield_rounded;
      chips.add(_ChipData(icon, policePresence, _getPoliceColor(policePresence)));
    }

    if (walkingAlone != null) {
      final icon = walkingAlone == 'Yes'
          ? Icons.check_circle_outline_rounded
          : walkingAlone == 'Maybe'
              ? Icons.help_outline_rounded
              : Icons.cancel_outlined;
      chips.add(_ChipData(icon, 'Walk Alone: $walkingAlone', _getWalkColor(walkingAlone)));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((chip) => _buildAssistChip(theme, chip)).toList(),
    );
  }

  Widget _buildAssistChip(ThemeData theme, _ChipData chip) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: chip.color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 15, color: chip.color),
          const SizedBox(width: 5),
          Text(
            chip.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: chip.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComment(ThemeData theme, String comment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        comment,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
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

class _ChipData {
  final IconData icon;
  final String label;
  final Color color;

  const _ChipData(this.icon, this.label, this.color);
}
