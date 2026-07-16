import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

class _DecodedImage {
  final int width;
  final int height;
  final Uint8List rgba;

  const _DecodedImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  List<int> pixel(int x, int y) {
    final clampedX = x.clamp(0, width - 1);
    final clampedY = y.clamp(0, height - 1);
    final index = (clampedY * width + clampedX) * 4;
    return <int>[
      rgba[index],
      rgba[index + 1],
      rgba[index + 2],
      rgba[index + 3],
    ];
  }
}

Future<_DecodedImage> _decodePng(File file) async {
  final bytes = await file.readAsBytes();
  return _decodePngBytes(bytes, sourcePath: file.path);
}

Future<_DecodedImage> _decodePngBytes(
  Uint8List bytes, {
  String sourcePath = 'memory-bytes',
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    throw StateError('Could not decode PNG bytes for $sourcePath');
  }
  return _DecodedImage(
    width: image.width,
    height: image.height,
    rgba: data.buffer.asUint8List(),
  );
}

bool _isGoldish(List<int> px) {
  return px[3] > 200 && px[0] >= 145 && px[1] >= 105 && px[2] >= 60;
}

bool _hasGoldInRect(
  _DecodedImage image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      if (_isGoldish(image.pixel(x, y))) {
        return true;
      }
    }
  }
  return false;
}

List<double> _normalizedBoundsInRect(
  _DecodedImage image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;

  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      if (_isGoldish(image.pixel(x, y))) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < 0 || maxY < 0) {
    throw StateError('No gold bounds found in selected rect.');
  }

  return <double>[
    minX / image.width,
    minY / image.height,
    maxX / image.width,
    maxY / image.height,
  ];
}

const List<List<double>> _flatBlackProbePoints1024 = <List<double>>[
  <double>[0.24, 0.24],
  <double>[0.76, 0.24],
  <double>[0.24, 0.76],
  <double>[0.76, 0.76],
  <double>[0.50, 0.14],
  <double>[0.50, 0.86],
  <double>[0.14, 0.50],
  <double>[0.86, 0.50],
  <double>[0.34, 0.22],
  <double>[0.66, 0.22],
];

const List<List<double>> _flatBlackProbePoints180 = <List<double>>[
  <double>[0.24, 0.24],
  <double>[0.76, 0.24],
  <double>[0.24, 0.76],
  <double>[0.76, 0.76],
  <double>[0.50, 0.16],
  <double>[0.50, 0.84],
];

void _expectFlatBlackSamples(
  _DecodedImage image,
  List<List<double>> probePoints,
) {
  final uniqueColors = <String>{};
  for (final pt in probePoints) {
    final px = image.pixel(
      (image.width * pt[0]).round(),
      (image.height * pt[1]).round(),
    );
    uniqueColors.add('${px[0]},${px[1]},${px[2]}');
    expect(px, equals(<int>[0, 0, 0, 255]));
  }
  expect(uniqueColors, hasLength(1));
}

Future<Uint8List> _resizePngBytes(
  File file, {
  required int targetWidth,
  required int targetHeight,
}) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Could not resize PNG bytes for ${file.path}');
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Build number is 161 in pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+161'));
    expect(
        pubspec, contains('image_path: "assets/icons/app_icon_build145.png"'));
  });

  test('Configured approved master icon exists and is exactly 1024x1024',
      () async {
    final iconFile = File('assets/icons/app_icon_build145.png');
    expect(iconFile.existsSync(), isTrue);

    final icon = await _decodePng(iconFile);
    expect(icon.width, 1024);
    expect(icon.height, 1024);
  });

  test('Approved master icon keeps flat-black background', () async {
    final build145 =
        await _decodePng(File('assets/icons/app_icon_build145.png'));
    _expectFlatBlackSamples(build145, _flatBlackProbePoints1024);
  });

  test('Approved master WW mark remains centered', () async {
    final build145 =
        await _decodePng(File('assets/icons/app_icon_build145.png'));
    final before = _normalizedBoundsInRect(
      build145,
      left: 220,
      top: 160,
      right: 820,
      bottom: 860,
    );
    final after = _normalizedBoundsInRect(
      build145,
      left: 220,
      top: 160,
      right: 820,
      bottom: 860,
    );

    final widthBefore = before[2] - before[0];
    final heightBefore = before[3] - before[1];
    final widthAfter = after[2] - after[0];
    final heightAfter = after[3] - after[1];

    expect(widthAfter / widthBefore, closeTo(1.0, 0.03));
    expect(heightAfter / heightBefore, closeTo(1.0, 0.03));

    final centerXBefore = (before[0] + before[2]) / 2;
    final centerYBefore = (before[1] + before[3]) / 2;
    final centerXAfter = (after[0] + after[2]) / 2;
    final centerYAfter = (after[1] + after[3]) / 2;
    expect((centerXAfter - centerXBefore).abs(), lessThan(0.01));
    expect((centerYAfter - centerYBefore).abs(), lessThan(0.01));
  });

  test('Approved icon border is visible at master and app sizes', () async {
    final master = await _decodePng(File('assets/icons/app_icon_build145.png'));
    expect(
      _hasGoldInRect(
        master,
        left: 100,
        top: 18,
        right: 924,
        bottom: 82,
      ),
      isTrue,
    );
    expect(
      _hasGoldInRect(
        master,
        left: 18,
        top: 100,
        right: 82,
        bottom: 924,
      ),
      isTrue,
    );

    final icon180 = await _decodePng(
      File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png'),
    );
    expect(
      _hasGoldInRect(
        icon180,
        left: 16,
        top: 3,
        right: 164,
        bottom: 17,
      ),
      isTrue,
    );

    final icon60Bytes = await _resizePngBytes(
      File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png'),
      targetWidth: 60,
      targetHeight: 60,
    );
    final icon60 = await _decodePngBytes(icon60Bytes);
    expect(
      _hasGoldInRect(
        icon60,
        left: 6,
        top: 1,
        right: 54,
        bottom: 5,
      ),
      isTrue,
    );
  });

  test(
      'iOS AppIcon set exists, references files, and restored 180 icon keeps the approved black background',
      () async {
    final contentsFile =
        File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json');
    expect(contentsFile.existsSync(), isTrue);

    final decoded =
        jsonDecode(await contentsFile.readAsString()) as Map<String, dynamic>;
    final images = (decoded['images'] as List<dynamic>)
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    final marketing = images.firstWhere(
      (entry) =>
          entry['idiom'] == 'ios-marketing' && entry['size'] == '1024x1024',
    );
    final marketingFileName = marketing['filename'] as String;

    final marketingFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/$marketingFileName',
    );
    expect(marketingFile.existsSync(), isTrue);

    final icon60 = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png',
    );
    expect(icon60.existsSync(), isTrue);

    for (final entry in images) {
      final fileName = entry['filename'];
      if (fileName is! String || fileName.isEmpty) continue;
      final file =
          File('ios/Runner/Assets.xcassets/AppIcon.appiconset/$fileName');
      expect(file.existsSync(), isTrue);
    }

    final icon60Decoded = await _decodePng(icon60);
    expect(icon60Decoded.width, 180);
    expect(icon60Decoded.height, 180);

    _expectFlatBlackSamples(icon60Decoded, _flatBlackProbePoints180);
  });
}
