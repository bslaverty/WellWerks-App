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

bool _pixelsEqual(List<int> a, List<int> b) {
  return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
}

List<int> _darkBounds(_DecodedImage image, {int lumaThreshold = 24}) {
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final px = image.pixel(x, y);
      final luma = (0.2126 * px[0]) + (0.7152 * px[1]) + (0.0722 * px[2]);
      if (px[3] > 200 && luma < lumaThreshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < 0 || maxY < 0) {
    throw StateError('No dark center region found in icon.');
  }

  return <int>[minX, minY, maxX, maxY];
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

  test('Build number is 135 in pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+135'));
    expect(
        pubspec, contains('image_path: "assets/icons/app_icon_build133.png"'));
  });

  test('Configured Build 133 master icon exists and is exactly 1024x1024',
      () async {
    final iconFile = File('assets/icons/app_icon_build133.png');
    expect(iconFile.existsSync(), isTrue);

    final icon = await _decodePng(iconFile);
    expect(icon.width, 1024);
    expect(icon.height, 1024);
  });

  test('Build 133 master hash differs from Build 129 master hash', () async {
    final build129 = File('assets/icons/app_icon_build129.png');
    final build133 = File('assets/icons/app_icon_build133.png');
    expect(build129.existsSync(), isTrue);
    expect(build133.existsSync(), isTrue);

    final hash129 = _fnv1a64Hex(await build129.readAsBytes());
    final hash133 = _fnv1a64Hex(await build133.readAsBytes());
    expect(hash133, isNot(equals(hash129)));
  });

  test('Build 133 master icon keeps opaque edge coverage and neutral black',
      () async {
    final icon = await _decodePng(File('assets/icons/app_icon_build133.png'));

    final blackProbePoints = <List<double>>[
      <double>[0.25, 0.25],
      <double>[0.75, 0.25],
      <double>[0.25, 0.75],
      <double>[0.75, 0.75],
      <double>[0.50, 0.35],
    ];
    for (final pt in blackProbePoints) {
      final px = icon.pixel(
        (icon.width * pt[0]).round(),
        (icon.height * pt[1]).round(),
      );
      expect(px[0], inInclusiveRange(0, 6));
      expect(px[1], inInclusiveRange(0, 6));
      expect(px[2], inInclusiveRange(0, 6));
      expect(px[3], 255);
    }

    final goldEdgePoints = <List<double>>[
      <double>[0.50, 0.0],
      <double>[0.0, 0.50],
      <double>[1.0, 0.50],
      <double>[0.50, 1.0],
      <double>[0.0, 0.0],
    ];
    for (final pt in goldEdgePoints) {
      final px = icon.pixel(
        (icon.width * pt[0]).round(),
        (icon.height * pt[1]).round(),
      );
      expect(px[3], greaterThanOrEqualTo(200));
      expect(px[0], inInclusiveRange(180, 226));
      expect(px[1], inInclusiveRange(135, 182));
      expect(px[2], inInclusiveRange(65, 112));

      expect(px[0], greaterThanOrEqualTo(180));
      expect(px[1], greaterThanOrEqualTo(135));
    }

    for (var x = 0; x < icon.width; x += 32) {
      expect(icon.pixel(x, 0)[3], greaterThanOrEqualTo(200));
      expect(icon.pixel(x, icon.height - 1)[3], greaterThanOrEqualTo(200));
    }
    for (var y = 0; y < icon.height; y += 32) {
      expect(icon.pixel(0, y)[3], greaterThanOrEqualTo(200));
      expect(icon.pixel(icon.width - 1, y)[3], greaterThanOrEqualTo(200));
    }
  });

  test('Build 133 center matches Build 124 and border is ~12% thinner',
      () async {
    final build124Resized = await _resizePngBytes(
      File('assets/icons/app_icon_build124.png'),
      targetWidth: 1024,
      targetHeight: 1024,
    );
    final build124 = await _decodePngBytes(
      build124Resized,
      sourcePath: 'assets/icons/app_icon_build124.png resized to 1024',
    );
    final build131Resized = await _resizePngBytes(
      File('assets/icons/app_icon_build131.png'),
      targetWidth: 1024,
      targetHeight: 1024,
    );
    final build131 = await _decodePngBytes(
      build131Resized,
      sourcePath: 'assets/icons/app_icon_build131.png resized to 1024',
    );
    final build133 =
        await _decodePng(File('assets/icons/app_icon_build133.png'));

    final width = build133.width;
    final height = build133.height;
    final x0 = (width * 0.15).floor();
    final x1 = (width * 0.85).ceil();
    final y0 = (height * 0.15).floor();
    final y1 = (height * 0.85).ceil();

    var centerDiff = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final inCenter = x >= x0 && x < x1 && y >= y0 && y < y1;
        final px133 = build133.pixel(x, y);
        if (inCenter) {
          if (!_pixelsEqual(px133, build124.pixel(x, y))) {
            centerDiff++;
          }
        }
      }
    }

    final dark131 = _darkBounds(build131);
    final dark133 = _darkBounds(build133);

    final t131 = (dark131[0] +
            dark131[1] +
            (build131.width - 1 - dark131[2]) +
            (build131.height - 1 - dark131[3])) /
        4.0;
    final t133 = (dark133[0] +
            dark133[1] +
            (build133.width - 1 - dark133[2]) +
            (build133.height - 1 - dark133[3])) /
        4.0;
    final reductionPct = ((t131 - t133) / t131) * 100.0;
    final centerDiffPct = (centerDiff * 100.0) / ((x1 - x0) * (y1 - y0));

    expect(centerDiffPct, lessThan(9.0),
        reason:
            'Build 133 center region should remain visually aligned to Build 124 after 1024 normalization.');
    expect(reductionPct, inInclusiveRange(10.0, 15.0),
        reason: 'Build 133 border must be reduced by ~10-15% from Build 131.');
  });

  test(
      'iOS AppIcon set exists, references files, and regenerated 180 hash differs from Build 128 output',
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

    final icon60Hash = _fnv1a64Hex(await icon60.readAsBytes());
    final build128Derived180 = await _resizePngBytes(
      File('assets/icons/app_icon_build128.png'),
      targetWidth: 180,
      targetHeight: 180,
    );
    final build128Derived180Hash = _fnv1a64Hex(build128Derived180);
    expect(icon60Hash, isNot(equals(build128Derived180Hash)));

    final icon60Decoded = await _decodePng(icon60);
    for (var x = 0; x < icon60Decoded.width; x += 8) {
      expect(icon60Decoded.pixel(x, 0)[3], 255);
      expect(icon60Decoded.pixel(x, icon60Decoded.height - 1)[3], 255);
    }
    for (var y = 0; y < icon60Decoded.height; y += 8) {
      expect(icon60Decoded.pixel(0, y)[3], 255);
      expect(icon60Decoded.pixel(icon60Decoded.width - 1, y)[3], 255);
    }

    final topCenter = icon60Decoded.pixel((icon60Decoded.width / 2).round(), 0);
    expect(topCenter[0], greaterThan(150));
    expect(topCenter[1], greaterThan(120));
    expect(topCenter[2], greaterThan(70));
  });
}
