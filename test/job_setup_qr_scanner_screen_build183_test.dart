import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/screens/job_setup_qr_scanner_screen.dart';
import 'package:wellwerks/services/job_setup_qr_service.dart';

class _ScannerHarness extends StatefulWidget {
  const _ScannerHarness();

  @override
  State<_ScannerHarness> createState() => _ScannerHarnessState();
}

class _ScannerHarnessState extends State<_ScannerHarness> {
  String result = 'none';

  Future<void> _openScanner() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => JobSetupQrScannerScreen(
          scannerBuilder: (context, onRawDetected) {
            return Column(
              children: [
                ElevatedButton(
                  onPressed: () => onRawDetected(
                    'WWJOBQR1C:sess1:1/2:AAAA',
                  ),
                  child: const Text('send_chunk_1'),
                ),
                ElevatedButton(
                  onPressed: () => onRawDetected(
                    'WWJOBQR1C:sess1:2/2:BBBB',
                  ),
                  child: const Text('send_chunk_2'),
                ),
                ElevatedButton(
                  onPressed: () => onRawDetected(
                    'WWJOBQR1:ZXlKc2IyTnNZWFpoYkM1amIyMHVjR0YwYUNJNkltbGs=',
                  ),
                  child: const Text('send_single'),
                ),
                ElevatedButton(
                  onPressed: () => onRawDetected('RANDOM_NOT_MATCHING'),
                  child: const Text('send_invalid'),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      result = value ?? 'cancelled';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: _openScanner,
            child: const Text('open_scanner'),
          ),
          Text('result:$result'),
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
    'Build 183 scanner shows chunk progress and can reset',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _ScannerHarness()),
      );

      await tester.tap(find.text('open_scanner'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Center the Job Setup QR code in view.'),
          findsOneWidget);

      await tester.tap(find.text('send_chunk_1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Captured 1/2 QR chunks...'), findsOneWidget);

      await tester.tap(find.text('Reset Scan'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Scan reset. Center the first Job Setup QR code'),
          findsOneWidget);
    },
  );

  testWidgets(
    'Build 183 scanner cancel returns null result',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _ScannerHarness()),
      );

      await tester.tap(find.text('open_scanner'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('result:cancelled'), findsOneWidget);
    },
  );

  testWidgets(
    'Build 183 scanner assembles chunks and pops encoded payload',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _ScannerHarness()),
      );

      await tester.tap(find.text('open_scanner'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('send_chunk_1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('send_chunk_2'));
      await tester.pumpAndSettle();

      expect(
        find.text('result:${JobSetupQrService.currentPrefix}AAAABBBB'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Build 183 scanner warns on non-matching code during chunk capture',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _ScannerHarness()),
      );

      await tester.tap(find.text('open_scanner'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('send_chunk_1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('send_invalid'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Detected a non-matching QR code while collecting Job Setup chunks.'),
        findsOneWidget,
      );
    },
  );
}
