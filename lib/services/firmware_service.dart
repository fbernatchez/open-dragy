import 'dart:convert';
import 'package:http/http.dart' as http;

class FirmwareService {
  // Replace this URL with the actual location of your manifest.json once hosted
  static const String manifestUrl =
      'https://open-dragy.fb-engineering.com/firmware/manifest.json';

  /// Fetches the manifest, finds the best matching firmware version (<= requestedVersion),
  /// and downloads its bytes.
  Future<List<int>> fetchBestFirmwareBytes(String requestedVersion) async {
    final manifestResponse = await http.get(Uri.parse(manifestUrl));
    if (manifestResponse.statusCode != 200) {
      throw Exception(
          'Failed to load firmware manifest (HTTP ${manifestResponse.statusCode})');
    }

    final List<dynamic> manifestData = jsonDecode(manifestResponse.body);
    if (manifestData.isEmpty) {
      throw Exception('Firmware manifest is empty');
    }

    // Filter available versions to only those <= requestedVersion
    final availableVersions = manifestData.where((entry) {
      final String entryVersion = entry['version'];
      return _compareVersions(entryVersion, requestedVersion) <= 0;
    }).toList();

    if (availableVersions.isEmpty) {
      throw Exception('No firmware found matching or below $requestedVersion');
    }

    // Sort descending and pick the highest available
    availableVersions.sort((a, b) => _compareVersions(b['version'], a['version']));
    final bestMatch = availableVersions.first;

    final String firmwareUrl = bestMatch['url'];

    // Download the actual firmware binary
    final firmwareResponse = await http.get(Uri.parse(firmwareUrl));
    if (firmwareResponse.statusCode != 200) {
      throw Exception(
          'Failed to download firmware binary (HTTP ${firmwareResponse.statusCode})');
    }

    return firmwareResponse.bodyBytes;
  }

  /// Helper to compare two semantic version strings (e.g., "1.0.2" and "1.0.4")
  /// Returns:
  ///   < 0 if v1 < v2
  ///     0 if v1 == v2
  ///   > 0 if v1 > v2
  int _compareVersions(String v1, String v2) {
    final p1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < p1.length && i < p2.length; i++) {
      if (p1[i] < p2[i]) return -1;
      if (p1[i] > p2[i]) return 1;
    }
    // If we get here, they are equal up to the checked length.
    if (p1.length < p2.length) return -1;
    if (p1.length > p2.length) return 1;
    return 0;
  }
}
