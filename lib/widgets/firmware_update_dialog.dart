import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../services/firmware_service.dart';

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

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFBF00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFBF00).withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFFBF00),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Do not unplug or disconnect the device during the update.',
              style: TextStyle(
                color: Color(0xFFFFBF00),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      title: Text(
        _isFlashing ? 'Updating Firmware' : 'Firmware Update Available',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isFlashing) ...[
            const Text(
              'A newer firmware version is recommended for optimal performance with this app version. Would you like to update now?',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            _buildWarningBanner(),
          ] else ...[
            Text(_status, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            if (!_isError && !_isComplete) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 16),
              _buildWarningBanner(),
            ],
          ],
        ],
      ),
      actions: [
        if (!_isFlashing) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
            ),
            onPressed: _startUpdate,
            icon: const Icon(Icons.system_update, size: 18, color: Colors.white),
            label: const Text('Update Now', style: TextStyle(color: Colors.white)),
          ),
        ] else if (_isError || _isComplete) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ],
    );
  }
}
