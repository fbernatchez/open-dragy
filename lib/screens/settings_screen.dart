import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dragy_provider.dart';
import 'ride_logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;
    final tempInCelsius = dragy.tempInCelsius;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Settings',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Units section
          _SectionHeader(label: 'Units'),
          _SettingsToggle(
            icon: Icons.speed,
            title: 'Unit in Metric',
            subtitle: isMetric ? 'km/h, km' : 'mph, miles',
            value: isMetric,
            onChanged: (v) => dragy.setMetric(v),
          ),
          _SettingsToggle(
            icon: Icons.thermostat,
            title: 'Temperature in Celsius',
            subtitle: tempInCelsius ? 'Displaying °C' : 'Displaying °F',
            value: tempInCelsius,
            onChanged: (v) => dragy.setTempInCelsius(v),
          ),
          _SettingsToggle(
            icon: Icons.timer_outlined,
            title: 'NHRA Rules',
            subtitle: dragy.useNhraRules
                ? 'Applies 1ft rollout and 66ft trap speed'
                : 'Standard timing without NHRA rules',
            value: dragy.useNhraRules,
            onChanged: (v) => dragy.setUseNhraRules(v),
          ),

          _SectionHeader(label: 'Display'),
          _SettingsToggle(
            icon: Icons.phone_android,
            title: dragy.pocketMode ? 'Pocket mode' : 'Always on',
            subtitle: dragy.pocketMode
                ? 'Screen may turn off; ongoing notification keeps timing alive'
                : 'Keeps display on while connected',
            // Switch ON = Always on (default). OFF = Pocket mode.
            value: !dragy.pocketMode,
            onChanged: (alwaysOn) => dragy.setPocketMode(!alwaysOn),
          ),

          _SectionHeader(label: 'Data'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.folder_special_outlined,
                color: Color(0xFF42A5F5),
                size: 22,
              ),
            ),
            title: Text(
              'OpenDragy data folder',
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              dragy.usesPublicDataFolder
                  ? dragy.durableDataFolderPath ?? 'OpenDragy at storage root'
                  : dragy.hasDurableDataFolder
                      ? 'Custom folder (SAF) — survives uninstall'
                      : 'Tap to allow file access & create /OpenDragy',
              style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () async {
              final ok = await dragy.pickDurableDataFolder();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? (dragy.usesPublicDataFolder
                              ? 'Using ${dragy.durableDataFolderPath}'
                              : 'Data folder linked.')
                          : 'Storage access not granted.',
                    ),
                  ),
                );
              }
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.timeline,
                color: Color(0xFF42A5F5),
                size: 22,
              ),
            ),
            title: Text(
              'Logger sessions',
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Share GPX / CSV with PC · filter by tags',
              style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RideLogsScreen()),
              );
            },
          ),

          _SectionHeader(label: 'About'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Color(0xFF42A5F5),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Version',
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dragy.appVersion.isNotEmpty
                            ? dragy.appVersion
                            : 'Loading...',
                        style: GoogleFonts.roboto(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          // App info
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text(
              'OpenDragy',
              style: GoogleFonts.comfortaa(
                color: Colors.white24,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.roboto(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: value
                ? const Color(0xFF1565C0).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: value ? const Color(0xFF42A5F5) : Colors.white38,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.roboto(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF42A5F5),
        activeTrackColor: const Color(0xFF1565C0),
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

