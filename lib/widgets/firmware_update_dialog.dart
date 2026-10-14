import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../services/firmware_service.dart';
import '../theme/app_theme.dart';

class FirmwareUpdateDialog extends StatefulWidget {
  final bool autoStart;

  const FirmwareUpdateDialog({
    super.key,
    this.autoStart = false,
  });

  @override
  State<FirmwareUpdateDialog> createState() => _FirmwareUpdateDialogState();
}

class _FirmwareUpdateDialogState extends State<FirmwareUpdateDialog> {
  bool _isFlashing = false;
  String _status = "Initializing...";
  double _progress = 0.0;
  bool _isError = false;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      _startUpdate();
    }
  }

  Future<void> _startUpdate() async {
    setState(() {
      _isFlashing = true;
      _status = "Fetching firmware manifest...";
      _progress = 0.0;
      _isError = false;
      _isComplete = false;
    });

    final dragy = Provider.of<DragyProvider>(context, listen: false);
    try {
      await dragy.performFirmwareUpdate(FirmwareService.minRecommendedFirmware, (p) {
        if (mounted) {
          setState(() {
            _status = "Flashing...";
            _progress = p;
          });
        }
      });
      if (mounted) {
        setState(() {
          _status = "Update complete! Device restarting.";
          _isComplete = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error: $e";
          _isError = true;
        });
      }
    }
  }

  Widget _buildWarningBanner(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.statusWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.statusWarning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colors.statusWarning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Do not unplug or disconnect the device during the update.',
              style: TextStyle(
                color: colors.statusWarning,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      title: Text(
        _isFlashing ? 'Updating Firmware' : 'Firmware Update Available',
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isFlashing) ...[
            Text(
              'A newer firmware version is recommended for optimal performance with this app version. Would you like to update now?',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            _buildWarningBanner(colors),
          ] else ...[
            Text(_status, style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 16),
            if (!_isError && !_isComplete) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: colors.subtleBorder,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
              const SizedBox(height: 16),
              _buildWarningBanner(colors),
            ],
          ],
        ],
      ),
      actions: [
        if (!_isFlashing) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Later', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.buttonForeground,
            ),
            onPressed: _startUpdate,
            icon: Icon(Icons.system_update, size: 18, color: colors.buttonForeground),
            label: Text('Update Now', style: TextStyle(color: colors.buttonForeground)),
          ),
        ] else if (_isError || _isComplete) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: colors.accent)),
          ),
        ],
      ],
    );
  }
}
