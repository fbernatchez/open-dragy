import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'run_history_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  const MainNavigationScreen({super.key, this.initialIndex = 0});

  static void switchToTab(BuildContext context, int index) {
    final state =
        context.findAncestorStateOfType<_MainNavigationScreenState>();
    if (state != null) {
      state.setIndex(index);
    } else {
      if (index == 1) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RunHistoryScreen()),
        );
      } else if (index == 2) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      }
    }
  }

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  final Set<int> _loadedTabs = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadedTabs.add(_currentIndex);
  }

  void setIndex(int index) {
    if (index >= 0 && index < 3) {
      setState(() {
        _currentIndex = index;
        _loadedTabs.add(index);
      });
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    final dragy = Provider.of<DragyProvider>(context, listen: false);
    if (dragy.metrics.isRunning) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.grey.shade900,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Run in progress. Finish or reset before switching tabs.',
                  style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final barColor = colors.background;
    final borderTopColor = colors.cardBorder;
    final selectedColor = colors.textPrimary;
    final unselectedColor = colors.textMuted;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const DashboardScreen(),
          _loadedTabs.contains(1)
              ? const RunHistoryScreen()
              : const SizedBox.shrink(),
          _loadedTabs.contains(2)
              ? const SettingsScreen()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: barColor,
          border: Border(
            top: BorderSide(
              color: borderTopColor,
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: barColor,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          elevation: 0,
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: GoogleFonts.roboto(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.roboto(
            fontWeight: FontWeight.normal,
          ),
          onTap: _onTabTapped,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.speed),
              label: 'Meter',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
