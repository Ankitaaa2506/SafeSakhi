import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/search_result.dart';
import '../theme/constants.dart';

enum SearchPanelState { history, loading, results, empty, error }

class SearchResultsOverlay extends StatelessWidget {
  final SearchPanelState state;
  final List<SearchResult> results;
  final List<SearchResult> history;
  final String? errorMessage;
  final String? currentQuery;
  final ValueChanged<SearchResult> onResultTap;
  final ValueChanged<SearchResult> onHistoryTap;
  final ValueChanged<SearchResult> onRemoveHistory;
  final VoidCallback onClearHistory;

  const SearchResultsOverlay({
    super.key,
    required this.state,
    required this.results,
    required this.history,
    this.errorMessage,
    this.currentQuery,
    required this.onResultTap,
    required this.onHistoryTap,
    required this.onRemoveHistory,
    required this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (state) {
      case SearchPanelState.loading:
        return _buildLoading();
      case SearchPanelState.results:
        return _buildResultsCard();
      case SearchPanelState.empty:
        return _buildEmptyState();
      case SearchPanelState.error:
        return _buildErrorState();
      case SearchPanelState.history:
        return _buildHistorySection();
    }
  }

  static final BoxDecoration _cardDecoration = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 20,
        offset: const Offset(0, 8),
        spreadRadius: 0,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 2),
        spreadRadius: 0,
      ),
    ],
  );

  Widget _buildLoading() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: _cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(AppColors.primaryBlue.withValues(alpha: 0.8)),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Searching...',
            style: TextStyle(color: AppColors.textHint, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: _cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_off, color: AppColors.primaryBlue, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'No places found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try a different search or check spelling',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: _cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? 'Unable to search places',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    if (history.isEmpty) return const SizedBox.shrink();
    return _buildHistoryCard();
  }

  Widget _buildHistoryCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: _cardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent Searches',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onClearHistory,
                  child: const Text(
                    'Clear All',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: history.length,
              itemBuilder: (context, index) => _buildHistoryItem(history[index], index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(SearchResult item, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 30)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onHistoryTap(item);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.chipBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(item.icon, style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          item.address,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => onRemoveHistory(item),
                child: const Icon(Icons.close, color: AppColors.textHint, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      constraints: const BoxConstraints(maxHeight: 450),
      decoration: _cardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                Text(
                  '${results.length} results',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                  ),
                ),
                const Spacer(),
                if (results.any((r) => r.distance != null))
                  const Text(
                    'Nearest first',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: results.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 66),
              itemBuilder: (context, index) => _buildResultItem(results[index], index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultItem(SearchResult result, int index) {
    final categoryColor = CategoryConfig.categoryColors[result.category] ?? AppColors.textHint;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 40)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onResultTap(result);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(result.icon, style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightText(result.name, currentQuery),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            SearchResult.categoryName(result.category),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: categoryColor,
                            ),
                          ),
                        ),
                        if (result.displayDistance.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.circle, size: 3, color: AppColors.textHint.withValues(alpha: 0.4)),
                          const SizedBox(width: 8),
                          Text(
                            result.displayDistance,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (result.address.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        result.address,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightText(String text, String? query) {
    if (query == null || query.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.black,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final start = lowerText.indexOf(lowerQuery);

    if (start == -1) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.black,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final end = start + query.length;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.black,
        ),
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }
}
