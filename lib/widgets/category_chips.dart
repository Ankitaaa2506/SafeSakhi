import 'package:flutter/material.dart';
import '../models/search_result.dart';
import '../theme/constants.dart';

class CategoryChips extends StatelessWidget {
  final SearchCategory? selectedCategory;
  final SearchCategory? loadingCategory;
  final ValueChanged<SearchCategory> onCategoryTap;

  const CategoryChips({
    super.key,
    this.selectedCategory,
    this.loadingCategory,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: CategoryConfig.chipCategories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = CategoryConfig.chipCategories[index];
          final isSelected = selectedCategory == category;
          final isLoading = loadingCategory == category;
          final color = CategoryConfig.categoryColors[category] ?? Colors.grey;

          return AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: isSelected ? 1.03 : 1.0,
            child: GestureDetector(
              onTap: isLoading ? null : () => onCategoryTap(category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.16),
                            color.withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : Colors.white.withValues(alpha: 0.94),
                  borderRadius: AppStyles.chipRadius,
                  border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.40)
                        : Colors.white.withValues(alpha: 0.75),
                    width: isSelected ? 1.4 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: isSelected ? 0.12 : 0.08),
                      blurRadius: isSelected ? 16 : 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: isLoading
                          ? SizedBox(
                              key: const ValueKey('loading'),
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                              ),
                            )
                          : Text(
                              SearchResult.categoryIcon(category),
                              key: ValueKey(category.name),
                              style: const TextStyle(fontSize: 14),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      SearchResult.categoryName(category),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? color : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
