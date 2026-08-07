import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/constants.dart';

class CustomSearchBar extends StatefulWidget {
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClose;
  final VoidCallback? onAvatarTap;
  final String? avatarUrl;
  final bool isSearching;

  const CustomSearchBar({
    super.key,
    this.focusNode,
    this.controller,
    this.onChanged,
    this.onClose,
    this.onAvatarTap,
    this.avatarUrl,
    this.isSearching = false,
  });

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandController;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.isSearching ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(CustomSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSearching && !oldWidget.isSearching) {
      _expandController.forward();
    } else if (!widget.isSearching && oldWidget.isSearching) {
      _expandController.reverse();
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.focusNode?.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          top: topPadding + (widget.isSearching ? 10 : 14),
          bottom: 8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.searchBackground.withValues(alpha: 0.96),
          borderRadius: AppStyles.searchBarRadius,
          border: Border.all(
            color: widget.isSearching
                ? AppColors.primaryBlue.withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.70),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink
                  .withValues(alpha: widget.isSearching ? 0.18 : 0.12),
              blurRadius: widget.isSearching ? 28 : 20,
              offset: Offset(0, widget.isSearching ? 12 : 8),
            ),
          ],
        ),
        child: Row(
          children: [
            if (widget.isSearching) _BackButton(onPressed: widget.onClose),
            Expanded(
              child: TextField(
                focusNode: widget.focusNode,
                controller: widget.controller,
                onChanged: widget.onChanged,
                autofocus: false,
                enableInteractiveSelection: true,
                onTap: () => widget.focusNode?.requestFocus(),
                style: const TextStyle(
                  fontSize: 17,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Search safe places nearby',
                  hintStyle: TextStyle(
                    color: AppColors.textHint.withValues(alpha: 0.70),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: widget.isSearching
                      ? null
                      : const Icon(
                          Icons.travel_explore_rounded,
                          color: AppColors.primaryBlue,
                          size: 21,
                        ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 24,
                  ),
                ),
              ),
            ),
            if (widget.isSearching && (widget.controller?.text.isNotEmpty ?? false))
              _ClearButton(
                onPressed: () {
                  widget.controller?.clear();
                  widget.onChanged?.call('');
                },
              ),
            if (!widget.isSearching)
              _AvatarButton(
                avatarUrl: widget.avatarUrl,
                onPressed: widget.onAvatarTap,
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _BackButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed?.call();
        },
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back, color: AppColors.primaryBlue, size: 22),
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ClearButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close, color: AppColors.textHint, size: 18),
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  final String? avatarUrl;
  final VoidCallback? onPressed;

  const _AvatarButton({this.avatarUrl, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed?.call();
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: avatarUrl == null ? AppColors.brandGradient : null,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: avatarUrl != null
              ? ClipOval(
                  child: Image.network(
                    avatarUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                )
              : const Center(
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
        ),
      ),
    );
  }
}
