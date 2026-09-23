import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Which action was picked from a [MessageActionMenu].
enum MessageAction { reply, delete }

/// Wraps [child] (a mail row or message bubble) so that long-pressing it
/// opens a small glass popover with Reply/Delete options, anchored right
/// next to that exact message - below it by default, or above it when the
/// message sits too close to the bottom of the screen for the popover to
/// fit. Unlike a bottom sheet or [GlassMenu]'s morph animation, the
/// message itself stays fully visible the whole time.
class MessageActionMenu extends StatefulWidget {
  final Widget child;
  final ValueChanged<MessageAction> onSelected;

  const MessageActionMenu({
    super.key,
    required this.child,
    required this.onSelected,
  });

  @override
  State<MessageActionMenu> createState() => _MessageActionMenuState();
}

class _MessageActionMenuState extends State<MessageActionMenu> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();
  Size? _anchorSize;

  void _open() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    _anchorSize = renderBox.size;

    // Decide whether the popover fits below the message; if not, flip it
    // to appear above instead.
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    const popoverHeight = 108.0; // two 44px rows + padding, approx.
    final spaceBelow = screenHeight - (anchorPosition.dy + _anchorSize!.height);
    _showAbove = spaceBelow < popoverHeight + 16;

    _overlayController.show();
  }

  void _close() => _overlayController.hide();

  bool _showAbove = false;

  void _select(MessageAction action) {
    _close();
    widget.onSelected(action);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _open,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => _buildOverlay(context),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final anchorHeight = _anchorSize?.height ?? 0;

    return Stack(
      children: [
        // Invisible barrier so tapping outside the popover dismisses it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
            child: const SizedBox.shrink(),
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: _showAbove ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: _showAbove ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, _showAbove ? -8 : 8),
          child: _PopoverCard(
            onSelect: _select,
          ),
        ),
      ],
    );
  }
}

class _PopoverCard extends StatelessWidget {
  final ValueChanged<MessageAction> onSelect;
  const _PopoverCard({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: GlassContainer(
        useOwnLayer: true,
        width: 180,
        shape: const LiquidRoundedSuperellipse(borderRadius: 16),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PopoverTile(
              icon: CupertinoIcons.arrowshape_turn_up_left_fill,
              label: 'Reply',
              iconColor: const Color(0xFF00E5FF),
              onTap: () => onSelect(MessageAction.reply),
            ),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            _PopoverTile(
              icon: CupertinoIcons.delete_solid,
              label: 'Delete',
              iconColor: const Color(0xFFFF6961),
              onTap: () => onSelect(MessageAction.delete),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopoverTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _PopoverTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                color: iconColor == const Color(0xFFFF6961) ? iconColor : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
