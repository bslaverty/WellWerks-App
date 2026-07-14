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

String _fnv1a64Hex(Uint8List bytes) {
  const int offset = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  var hash = offset;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0').toUpperCase();
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
  <double>[0.18, 0.18],
  <double>[0.82, 0.18],
  <double>[0.18, 0.82],
  <double>[0.82, 0.82],
  <double>[0.50, 0.10],
  <double>[0.50, 0.90],
  <double>[0.12, 0.50],
  <double>[0.88, 0.50],
  <double>[0.36, 0.18],
  <double>[0.64, 0.18],
];

const List<List<double>> _flatBlackProbePoints180 = <List<double>>[
  <double>[0.18, 0.18],
  <double>[0.82, 0.18],
  <double>[0.18, 0.82],
  <double>[0.82, 0.82],
  <double>[0.50, 0.10],
  <double>[0.50, 0.90],
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

  test('Build number is 141 in pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+141'));
    expect(
        pubspec, contains('image_path: "assets/icons/app_icon_build141.png"'));
  });

  test('Configured Build 141 master icon exists and is exactly 1024x1024',
      () async {
    final iconFile = File('assets/icons/app_icon_build141.png');
    expect(iconFile.existsSync(), isTrue);

    final icon = await _decodePng(iconFile);
    expect(icon.width, 1024);
    expect(icon.height, 1024);
  });

  test('Build 141 master hash differs from Build 140 master hash', () async {
    final build140 = File('assets/icons/app_icon_build140.png');
    final build141 = File('assets/icons/app_icon_build141.png');
    expect(build140.existsSync(), isTrue);
    expect(build141.existsSync(), isTrue);

    final hash140 = _fnv1a64Hex(await build140.readAsBytes());
    final hash141 = _fnv1a64Hex(await build141.readAsBytes());
    expect(hash141, isNot(equals(hash140)));
  });

  test('Build 141 master icon keeps flat-black background', () async {
    final build141 =
        await _decodePng(File('assets/icons/app_icon_build141.png'));
    _expectFlatBlackSamples(build141, _flatBlackProbePoints1024);
  });

  test('Build 141 WW mark is uniformly reduced by about seven percent',
      () async {
    final build140 =
        await _decodePng(File('assets/icons/app_icon_build140.png'));
    final build141 =
        await _decodePng(File('assets/icons/app_icon_build141.png'));
    final before = _normalizedBoundsInRect(
      build140,
      left: 140,
      top: 140,
      right: 900,
      bottom: 900,
    );
    final after = _normalizedBoundsInRect(
      build141,
      left: 140,
      top: 140,
      right: 900,
      bottom: 900,
    );

    final widthBefore = before[2] - before[0];
    final heightBefore = before[3] - before[1];
    final widthAfter = after[2] - after[0];
    final heightAfter = after[3] - after[1];

    expect(widthAfter / widthBefore, closeTo(0.93, 0.02));
    expect(heightAfter / heightBefore, closeTo(0.93, 0.02));

    final centerXBefore = (before[0] + before[2]) / 2;
    final centerYBefore = (before[1] + before[3]) / 2;
    final centerXAfter = (after[0] + after[2]) / 2;
    final centerYAfter = (after[1] + after[3]) / 2;
    expect((centerXAfter - centerXBefore).abs(), lessThan(0.01));
    expect((centerYAfter - centerYBefore).abs(), lessThan(0.01));
  });

  test('Build 141 inset gold border is visible at master and app sizes',
      () async {
    final master = await _decodePng(File('assets/icons/app_icon_build141.png'));
    expect(
      _hasGoldInRect(
        master,
        left: 120,
        top: 4,
        right: 904,
        bottom: 24,
      ),
      isTrue,
    );
    expect(
      _hasGoldInRect(
        master,
        left: 4,
        top: 120,
        right: 24,
        bottom: 904,
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
        left: 18,
        top: 0,
        right: 162,
        bottom: 6,
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
        left: 7,
        top: 0,
        right: 53,
        bottom: 2,
      ),
      isTrue,
    );
  });

  test(
      'iOS AppIcon set exists, references files, and regenerated 180 hash differs from Build 139 output',
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

    final icon60Hash = _fnv1a64Hex(await icon60.readAsBytes());
    final build139Derived180 = await _resizePngBytes(
      File('assets/icons/app_icon_build139.png'),
      targetWidth: 180,
      targetHeight: 180,
    );
    final build139Derived180Hash = _fnv1a64Hex(build139Derived180);
    expect(icon60Hash, isNot(equals(build139Derived180Hash)));

    _expectFlatBlackSamples(icon60Decoded, _flatBlackProbePoints180);
  });
}
