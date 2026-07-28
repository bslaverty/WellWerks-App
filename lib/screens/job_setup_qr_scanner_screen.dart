import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/job_setup_qr_service.dart';
import '../widgets/app_header.dart';

typedef JobSetupQrScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onRawDetected,
);

class JobSetupQrScannerScreen extends StatefulWidget {
  const JobSetupQrScannerScreen({
    super.key,
    this.scannerBuilder,
  });

  final JobSetupQrScannerBuilder? scannerBuilder;

  @override
  State<JobSetupQrScannerScreen> createState() =>
      _JobSetupQrScannerScreenState();
}

class _JobSetupQrScannerScreenState extends State<JobSetupQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final JobSetupQrService _qrService = const JobSetupQrService();
  bool _handled = false;
  String? _activeSessionId;
  int _activeTotal = 0;
  final Map<int, String> _chunkFrames = <int, String>{};
  String _scanStatus =
      'Center the Job Setup QR code in view. Large Job Setups may require scanning multiple QR codes.';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = (barcode.rawValue ?? '').trim();
      if (value.isEmpty) continue;

      _handleRawScanValue(value);
      if (_handled) return;
    }
  }

  void _handleRawScanValue(String value) {
    if (_handled) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    try {
      final chunk = _qrService.tryParseChunkFrame(trimmed);
      if (chunk == null) {
        if (_chunkFrames.isNotEmpty) {
          setState(() {
            _scanStatus =
                'Detected a non-matching QR code while collecting Job Setup chunks. Keep scanning this set or tap Reset Scan.';
          });
          return;
        }
        _handled = true;
        Navigator.of(context).pop(trimmed);
        return;
      }

      if (_activeSessionId == null) {
        _activeSessionId = chunk.sessionId;
        _activeTotal = chunk.total;
      }

      if (_activeSessionId != chunk.sessionId || _activeTotal != chunk.total) {
        setState(() {
          _activeSessionId = chunk.sessionId;
          _activeTotal = chunk.total;
          _chunkFrames
            ..clear()
            ..[chunk.index] = trimmed;
          _scanStatus = 'Detected new QR set. Captured 1/$_activeTotal.';
        });
        return;
      }

      if (!_chunkFrames.containsKey(chunk.index)) {
        _chunkFrames[chunk.index] = trimmed;
        setState(() {
          _scanStatus =
              'Captured ${_chunkFrames.length}/$_activeTotal QR chunks...';
        });
      }

      if (_chunkFrames.length == _activeTotal) {
        final assembled = _qrService.assembleChunkFrames(_chunkFrames.values);
        _handled = true;
        Navigator.of(context).pop(assembled);
        return;
      }
    } on FormatException catch (error) {
      setState(() {
        _scanStatus = error.message;
      });
    }
  }

  void _resetChunkScan() {
    setState(() {
      _activeSessionId = null;
      _activeTotal = 0;
      _chunkFrames.clear();
      _scanStatus =
          'Scan reset. Center the first Job Setup QR code to begin again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Scan Job Setup QR', showBack: true),
      body: Column(
        children: [
          Expanded(
            child: widget.scannerBuilder != null
                ? widget.scannerBuilder!(context, _handleRawScanValue)
                : MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              _scanStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chunkFrames.isEmpty ? null : _resetChunkScan,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset Scan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
