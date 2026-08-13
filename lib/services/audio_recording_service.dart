import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecordingService {
  final _record = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSubscription;
  final Queue<Uint8List> _buffer = Queue<Uint8List>();
  
  static const int sampleRate = 44100;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit
  static const int maxBufferSeconds = 3;
  static const int maxBufferBytes = sampleRate * numChannels * bytesPerSample * maxBufferSeconds;
  
  int _currentBufferBytes = 0;
  bool _isCommitted = false;
  File? _pcmFile;
  IOSink? _fileSink;
  int _totalWrittenBytes = 0;

  Future<void> startArmedBuffer() async {
    if (await _record.hasPermission()) {
      _buffer.clear();
      _currentBufferBytes = 0;
      _isCommitted = false;
      _fileSink = null;
      _totalWrittenBytes = 0;
      
      final stream = await _record.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
      ));
      
      _streamSubscription = stream.listen((data) {
        if (_fileSink == null) {
          _buffer.add(data);
          if (!_isCommitted) {
            _currentBufferBytes += data.length;
            while (_currentBufferBytes > maxBufferBytes && _buffer.isNotEmpty) {
              final dropped = _buffer.removeFirst();
              _currentBufferBytes -= dropped.length;
            }
          }
        } else {
          _fileSink!.add(data);
          _totalWrittenBytes += data.length;
        }
      });
    }
  }

  Future<void> commitLaunch() async {
    if (_streamSubscription == null || _isCommitted) return;
    _isCommitted = true;
    
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'run_audio_${DateTime.now().millisecondsSinceEpoch}.pcm';
    _pcmFile = File('${dir.path}/$filename');
    final sink = _pcmFile!.openWrite();
    
    // Write whatever is in the buffer
    for (final chunk in _buffer) {
      sink.add(chunk);
      _totalWrittenBytes += chunk.length;
    }
    _buffer.clear();
    
    _fileSink = sink;
    _isCommitted = true;
  }

  Future<Map<String, dynamic>?> stopAndSaveRun() async {
    await _stopAndCleanup();
    
    if (_pcmFile != null && _totalWrittenBytes > 0) {
      // Calculate actual buffered seconds before it was committed
      final double bufferedSeconds = _currentBufferBytes / (sampleRate * numChannels * bytesPerSample);
      
      final pcmData = await _pcmFile!.readAsBytes();
      
      final dir = await getApplicationDocumentsDirectory();
      final wavFilename = 'run_audio_${DateTime.now().millisecondsSinceEpoch}.wav';
      final wavFile = File('${dir.path}/$wavFilename');
      
      final header = _buildWavHeader(_totalWrittenBytes);
      final wavSink = wavFile.openWrite();
      wavSink.add(header);
      wavSink.add(pcmData);
      await wavSink.flush();
      await wavSink.close();
      
      try {
        await _pcmFile!.delete();
      } catch (_) {}
      
      _pcmFile = null;
      return {
        'path': wavFile.path,
        'offset': bufferedSeconds,
      };
    }
    return null;
  }

  Future<void> abort() async {
    await _stopAndCleanup();
    if (_pcmFile != null) {
      try {
        await _pcmFile!.delete();
      } catch (_) {}
      _pcmFile = null;
    }
  }

  Future<void> _stopAndCleanup() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _record.stop();
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
  }

  Uint8List _buildWavHeader(int dataLength) {
    final byteData = ByteData(44);
    
    // "RIFF"
    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);
    
    // File size - 8
    byteData.setUint32(4, 36 + dataLength, Endian.little);
    
    // "WAVE"
    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);
    
    // "fmt "
    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);
    
    // Subchunk1Size (16 for PCM)
    byteData.setUint32(16, 16, Endian.little);
    
    // AudioFormat (1 for PCM)
    byteData.setUint16(20, 1, Endian.little);
    
    // NumChannels
    byteData.setUint16(22, numChannels, Endian.little);
    
    // SampleRate
    byteData.setUint32(24, sampleRate, Endian.little);
    
    // ByteRate
    byteData.setUint32(28, sampleRate * numChannels * bytesPerSample, Endian.little);
    
    // BlockAlign
    byteData.setUint16(32, numChannels * bytesPerSample, Endian.little);
    
    // BitsPerSample
    byteData.setUint16(34, bytesPerSample * 8, Endian.little);
    
    // "data"
    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);
    
    // Subchunk2Size (data length)
    byteData.setUint32(40, dataLength, Endian.little);
    
    return byteData.buffer.asUint8List();
  }

  void dispose() {
    _record.dispose();
  }
}
