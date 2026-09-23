import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Plain, transparent top header used in place of [GlassAppBar].
///
/// [GlassAppBar] renders its own glass "surface" (via AdaptiveGlass), and
/// that surface's shader always draws a rim-light/edge highlight along its
/// bottom edge - that's what shows up as a hard partition line under the
/// status bar. There's no property to turn that off; it's how the glass
/// shader represents the panel's edge. Since a plain background has no
/// separate surface for the shader to draw an edge against, using a bare
/// Row here (with glass only on the small circular icon buttons, where a
/// rim highlight reads as normal button styling rather than a seam) removes
/// the partition entirely while keeping the same back-button/actions API.
class SimpleHeader extends StatelessWidget implements PreferredSizeWidget {
  const SimpleHeader({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: preferredSize.height,
          child: Row(
            children: [
              if (leading != null) leading!,
              Expanded(
                child: centerTitle
                    ? Center(child: title ?? const SizedBox.shrink())
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: title ?? const SizedBox.shrink(),
                        ),
                      ),
              ),
              if (actions != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: actions!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
