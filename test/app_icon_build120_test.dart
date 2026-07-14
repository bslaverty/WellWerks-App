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
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    throw StateError('Could not decode PNG bytes for ${file.path}');
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

  test('Build number is 130 in pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+130'));
    expect(
        pubspec, contains('image_path: "assets/icons/app_icon_build130.png"'));
  });

  test('Configured Build 130 master icon exists and is at least 1024x1024',
      () async {
    final iconFile = File('assets/icons/app_icon_build130.png');
    expect(iconFile.existsSync(), isTrue);

    final icon = await _decodePng(iconFile);
    expect(icon.width, greaterThanOrEqualTo(1024));
    expect(icon.height, greaterThanOrEqualTo(1024));
  });

  test('Build 130 master hash differs from Build 129 master hash', () async {
    final build129 = File('assets/icons/app_icon_build129.png');
    final build130 = File('assets/icons/app_icon_build130.png');
    expect(build129.existsSync(), isTrue);
    expect(build130.existsSync(), isTrue);

    final hash129 = _fnv1a64Hex(await build129.readAsBytes());
    final hash130 = _fnv1a64Hex(await build130.readAsBytes());
    expect(hash130, isNot(equals(hash129)));
  });

  test('Build 130 master icon keeps opaque edge coverage and neutral black',
      () async {
    final icon = await _decodePng(File('assets/icons/app_icon_build130.png'));

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
      expect(px[3], 255);
      expect(px[0], inInclusiveRange(206, 220));
      expect(px[1], inInclusiveRange(162, 176));
      expect(px[2], inInclusiveRange(90, 106));

      expect(px[0], greaterThanOrEqualTo(206));
      expect(px[1], greaterThanOrEqualTo(162));
    }

    for (var x = 0; x < icon.width; x += 32) {
      expect(icon.pixel(x, 0)[3], 255);
      expect(icon.pixel(x, icon.height - 1)[3], 255);
    }
    for (var y = 0; y < icon.height; y += 32) {
      expect(icon.pixel(0, y)[3], 255);
      expect(icon.pixel(icon.width - 1, y)[3], 255);
    }
  });

  test('Build 130 center uses Build 124 while border preserves Build 129 ring',
      () async {
    final build124 =
        await _decodePng(File('assets/icons/app_icon_build124.png'));
    final build129 =
        await _decodePng(File('assets/icons/app_icon_build129.png'));
    final build130 =
        await _decodePng(File('assets/icons/app_icon_build130.png'));

    final width = build130.width;
    final height = build130.height;
    final x0 = (width * 0.15).floor();
    final x1 = (width * 0.85).ceil();
    final y0 = (height * 0.15).floor();
    final y1 = (height * 0.85).ceil();

    var centerDiff = 0;
    var borderDiff = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final inCenter = x >= x0 && x < x1 && y >= y0 && y < y1;
        final px130 = build130.pixel(x, y);
        if (inCenter) {
          if (!_pixelsEqual(px130, build124.pixel(x, y))) {
            centerDiff++;
          }
        } else {
          if (!_pixelsEqual(px130, build129.pixel(x, y))) {
            borderDiff++;
          }
        }
      }
    }

    expect(centerDiff, 0,
        reason: 'Build 130 center region must match Build 124 exactly.');
    expect(borderDiff, 0,
        reason: 'Build 130 border region must match Build 129 exactly.');
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
