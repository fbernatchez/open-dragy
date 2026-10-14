import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../widgets/firmware_update_dialog.dart';
import '../services/firmware_service.dart';
import '../widgets/box_pivot_preview.dart';
import '../theme/app_theme.dart';
import 'test_selection_screen.dart';
import 'garage_screen.dart';

class SettingsScreen extends StatelessWidget {
  static const String minRecommendedFirmware =
      FirmwareService.minRecommendedFirmware;

  static bool isUpdateAvailable(String currentVersion) =>
      FirmwareService.isUpdateAvailable(currentVersion);

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;
    final tempInCelsius = dragy.tempInCelsius;
    final themeMode = dragy.themeMode;
    final useNhraRules = dragy.useNhraRules;
    final enableTts = dragy.enableTts;
    final enableAudioRecording = dragy.enableAudioRecording;
    final isConnected = dragy.isConnected;
    final appVersion = dragy.appVersion;
    final firmwareVersion = dragy.firmwareVersion;
    final colors = context.colors;
    final cardColor = colors.cardBackground;
    final borderColor = colors.cardBorder;
    final titleColor = colors.textPrimary;
    final subtitleColor = colors.textMuted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Appearance section
          _SectionHeader(label: 'Appearance'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF9C27B0).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.brightness_6_rounded,
                  color: Color(0xFFBA68C8),
                  size: 22,
                ),
              ),
              title: Text(
                'Theme',
                style: AppTheme.font(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _themeModeLabel(themeMode),
                style: AppTheme.font(
                  color: subtitleColor,
                  fontSize: 12,
                ),
              ),
              onTap: () => _showThemeDialog(context, dragy),
            ),
          ),

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

          _SectionHeader(label: 'Rules'),
          _SettingsToggle(
            icon: Icons.timer_outlined,
            title: 'NHRA Rules',
            subtitle: useNhraRules
                ? 'Applies 1ft rollout and 66ft trap speed'
                : 'Standard timing without NHRA rules',
            value: useNhraRules,
            onChanged: (v) => dragy.setUseNhraRules(v),
          ),

          _SectionHeader(label: 'Media'),
          _SettingsToggle(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice Announcements',
            subtitle: enableTts
                ? 'Announces completed milestones'
                : 'TTS is disabled',
            value: enableTts,
            onChanged: (v) => dragy.setEnableTts(v),
          ),
          _SettingsToggle(
            icon: Icons.mic_none,
            title: 'Audio Recording',
            subtitle: enableAudioRecording
                ? 'Records audio during runs'
                : 'Microphone recording is disabled',
            value: enableAudioRecording,
            onChanged: (v) => dragy.setEnableAudioRecording(v),
          ),

          _SectionHeader(label: 'Garage'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_car_outlined,
                  color: Color(0xFF42A5F5),
                  size: 22,
                ),
              ),
              title: Text(
                'Garage',
                style: AppTheme.font(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Manage vehicles',
                style: AppTheme.font(color: subtitleColor, fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: subtitleColor),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GarageScreen(),
                  ),
                );
              },
            ),
          ),

          _SectionHeader(label: 'Tests'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.checklist,
                  color: Color(0xFF42A5F5),
                  size: 22,
                ),
              ),
              title: Text(
                'Active Tests',
                style: AppTheme.font(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Select which tests to track',
                style: AppTheme.font(color: subtitleColor, fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: subtitleColor),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TestSelectionScreen(),
                  ),
                );
              },
            ),
          ),

          _SectionHeader(label: 'Mounting & Sensor'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  color: Color(0xFF42A5F5),
                  size: 22,
                ),
              ),
              title: Text(
                'Box Pivot Orientation',
                style: AppTheme.font(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Set device mounting orientation',
                style: AppTheme.font(color: subtitleColor, fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: subtitleColor),
              onTap: () => _showBoxPivotDialog(context),
            ),
          ),

          _SectionHeader(label: 'About'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.15),
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
                        style: AppTheme.font(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        appVersion.isNotEmpty
                            ? 'App: $appVersion'
                            : 'App: Loading...',
                        style: AppTheme.font(
                          color: subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                      if (isConnected &&
                          firmwareVersion.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Firmware: $firmwareVersion',
                          style: AppTheme.font(
                            color: subtitleColor,
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

          if (isConnected &&
              SettingsScreen.isUpdateAvailable(firmwareVersion)) ...[
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
                style: AppTheme.font(color: subtitleColor, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.dark:
        return 'Dark mode';
      case ThemeMode.light:
        return 'Light mode';
    }
  }

  void _showThemeDialog(BuildContext context, DragyProvider dragy) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Theme',
            style: AppTheme.brandFont(
              color: colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: RadioGroup<ThemeMode>(
            groupValue: dragy.themeMode,
            onChanged: (mode) {
              if (mode != null) {
                dragy.setThemeMode(mode);
                Navigator.pop(ctx);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: colors.accent,
                  title: Text(
                    'System default',
                    style: AppTheme.font(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: colors.accent,
                  title: Text(
                    'Dark mode',
                    style: AppTheme.font(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: colors.accent,
                  title: Text(
                    'Light mode',
                    style: AppTheme.font(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showBoxPivotDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return const BoxPivotDialog();
      },
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

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.font(
          color: context.colors.textMuted,
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
    final colors = context.colors;
    final cardColor = colors.cardBackground;
    final borderColor = colors.cardBorder;
    final titleColor = colors.textPrimary;
    final subtitleColor = colors.textMuted;
    final isDark = context.isDark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: value
                ? const Color(0xFF1565C0).withValues(alpha: 0.2)
                : colors.subtleBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: value ? const Color(0xFF42A5F5) : subtitleColor,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: AppTheme.font(
            color: titleColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTheme.font(color: subtitleColor, fontSize: 12),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF42A5F5),
        activeTrackColor: const Color(0xFF1565C0),
        inactiveThumbColor: isDark ? subtitleColor : const Color(0xFF8E8E93),
        inactiveTrackColor: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
