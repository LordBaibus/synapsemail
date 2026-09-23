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
    return Scaffold(
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
        tabs: const [
          GlassBottomBarTab(
            label: 'Inbox',
            icon: CupertinoIcons.tray,
            selectedIcon: CupertinoIcons.tray_fill,
            glowColor: Color(0xFF00E5FF),
          ),
          GlassBottomBarTab(
            label: 'Sent',
            icon: CupertinoIcons.paperplane,
            selectedIcon: CupertinoIcons.paperplane_fill,
            glowColor: Color(0xFF00E5FF),
          ),
          GlassBottomBarTab(
            label: 'Profile',
            icon: CupertinoIcons.person,
            selectedIcon: CupertinoIcons.person_fill,
            glowColor: Color(0xFF6C5CE7),
          ),
        ],
      ),
    );
  }
}
