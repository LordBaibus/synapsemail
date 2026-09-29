import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../widgets/simple_header.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';

/// App shell shown after login: hosts the three main destinations (Inbox,
/// Sent, Profile) behind a [GlassBottomBar], replacing the old top app bar
/// + in-page tab bar. The compose action moves with the current tab as a
/// floating action button, shown only on the mail tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final _inboxKey = GlobalKey<InboxScreenState>();
  final _sentKey = GlobalKey<InboxScreenState>();

  static const _titles = ['Inbox', 'Sent', 'Profile'];

  void _onTabSelected(int index) {
    if (index == _selectedIndex) {
      // Re-tapping the current mail tab refreshes its list.
      if (index == 0) _inboxKey.currentState?.refresh();
      if (index == 1) _sentKey.currentState?.refresh();
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _openCompose() async {
    final key = _selectedIndex == 1 ? _sentKey : _inboxKey;
    await key.currentState?.openCompose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole scaffold - body AND the area behind the bottom nav bar -
    // shares one background wash, fixed to the app's base accent so it
    // never changes between tabs or shows a seam while swiping/switching.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.8),
          radius: 1.6,
          colors: [
            Color(0x1A6C5CE7), // _accent at ~10% alpha
            Colors.transparent,
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SimpleHeader(
          title: Text(
            _titles[_selectedIndex],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              IndexedStack(
                index: _selectedIndex,
                children: [
                  InboxScreen(key: _inboxKey, folder: 'inbox'),
                  InboxScreen(key: _sentKey, folder: 'sent'),
                  const ProfileScreen(),
                ],
              ),
              if (_selectedIndex != 2)
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: GlassIconButton(
                    icon: CupertinoIcons.pencil,
                    size: 56,
                    onPressed: _openCompose,
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: GlassBottomBar(
          selectedIndex: _selectedIndex,
          onTabSelected: _onTabSelected,
          // The bar's default glass tint is neutral white, which reads as
          // a different shade from the app's purple/dark background no
          // matter what sits behind it. Tint the glass itself to match.
          glassSettings: const LiquidGlassSettings(
            thickness: 30,
            blur: 3,
            chromaticAberration: 0.3,
            lightIntensity: 0.6,
            refractiveIndex: 1.59,
            saturation: 0.9,
            ambientStrength: 1,
            lightAngle: 0.7853981633974483,
            glassColor: Color(0x4D6C5CE7), // accent purple at ~30% alpha
          ),
          // Fully transparent makes the pill invisible entirely (the glass
          // indicator needs some alpha to render its shape). Use a neutral
          // white at low opacity so the "current page" pill still shows
          // as a plain glass shape, with no color/glow of its own.
          indicatorColor: Colors.white.withValues(alpha: 0.16),
          // Default tabPadding leaves a visible gap between the pill and
          // the tab's own bounds; zero it so the pill fills the tab.
          tabPadding: EdgeInsets.zero,
          // MaskingQuality.off hides the pill entirely at rest (it only
          // fades in while actively pressed/dragged), so go back to the
          // default high-quality mode, which stays visible at rest - the
          // mid-drag seam is a lesser issue than an invisible indicator.
          maskingQuality: MaskingQuality.high,
          // No glowColor on any tab - selection is shown by the plain
          // pill shape and the filled selectedIcon alone, no glow effect.
          tabs: const [
            GlassBottomBarTab(
              label: 'Inbox',
              icon: CupertinoIcons.tray,
              selectedIcon: CupertinoIcons.tray_fill,
            ),
            GlassBottomBarTab(
              label: 'Sent',
              icon: CupertinoIcons.paperplane,
              selectedIcon: CupertinoIcons.paperplane_fill,
            ),
            GlassBottomBarTab(
              label: 'Profile',
              icon: CupertinoIcons.person,
              selectedIcon: CupertinoIcons.person_fill,
            ),
          ],
        ),
      ),
    );
  }
}
