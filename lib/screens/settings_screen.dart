import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/dragy_provider.dart';

class SettingsScreen extends StatelessWidget {
  static const String minRecommendedFirmware = "1.0.2";

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
          _SettingsToggle(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice Announcements',
            subtitle: dragy.enableTts
                ? 'Announces completed milestones'
                : 'TTS is disabled',
            value: dragy.enableTts,
            onChanged: (v) => dragy.setEnableTts(v),
          ),
          _SettingsToggle(
            icon: Icons.mic_none,
            title: 'Audio Recording',
            subtitle: dragy.enableAudioRecording
                ? 'Records audio during runs'
                : 'Microphone recording is disabled',
            value: dragy.enableAudioRecording,
            onChanged: (v) => dragy.setEnableAudioRecording(v),
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
                            ? 'App: ${dragy.appVersion}'
                            : 'App: Loading...',
                        style: GoogleFonts.roboto(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      if (dragy.isConnected && dragy.firmwareVersion.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Firmware: ${dragy.firmwareVersion}',
                          style: GoogleFonts.roboto(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (dragy.isConnected) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: () => _showFirmwareUpdateDialog(context, dragy),
                icon: const Icon(Icons.system_update),
                label: const Text('Update Firmware'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Recommended firmware: v${SettingsScreen.minRecommendedFirmware} or higher for this app version.',
                style: GoogleFonts.roboto(
                  color: Colors.white38,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 32),
          // App info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text(
              'OpenDragy',
              style: GoogleFonts.comfortaa(color: Colors.white24, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showFirmwareUpdateDialog(BuildContext context, DragyProvider dragy) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const FirmwareUpdateDialog();
      },
    );
  }
}

class FirmwareUpdateDialog extends StatefulWidget {
  const FirmwareUpdateDialog({super.key});

  @override
  State<FirmwareUpdateDialog> createState() => _FirmwareUpdateDialogState();
}

class _FirmwareUpdateDialogState extends State<FirmwareUpdateDialog> {
  String status = "Initializing...";
  double progress = 0.0;
  bool isError = false;
  bool isComplete = false;

  @override
  void initState() {
    super.initState();
    _startUpdate();
  }

  Future<void> _startUpdate() async {
    final dragy = Provider.of<DragyProvider>(context, listen: false);
    try {
      setState(() {
        status = "Fetching firmware manifest...";
      });
      await dragy.performFirmwareUpdate(SettingsScreen.minRecommendedFirmware, (p) {
        setState(() {
          status = "Flashing...";
          progress = p;
        });
      });
      setState(() {
        status = "Update complete! Device restarting.";
        isComplete = true;
      });
    } catch (e) {
      setState(() {
        status = "Error: $e";
        isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      title: const Text('Firmware Update', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          if (!isError && !isComplete)
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
        ],
      ),
      actions: [
        if (isError || isComplete)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
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
          style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF42A5F5),
        activeTrackColor: const Color(0xFF1565C0),
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
