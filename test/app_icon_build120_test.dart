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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Build number is 121 in pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+121'));
    expect(
        pubspec, contains('image_path: "assets/icons/app_icon_build121.png"'));
  });

  test('Master app icon exists and is at least 1024x1024', () async {
    final iconFile = File('assets/icons/app_icon_build121.png');
    expect(iconFile.existsSync(), isTrue);

    final icon = await _decodePng(iconFile);
    expect(icon.width, greaterThanOrEqualTo(1024));
    expect(icon.height, greaterThanOrEqualTo(1024));
  });

  test(
      'Master app icon restores older rich colors and full opaque edge coverage',
      () async {
    final icon = await _decodePng(File('assets/icons/app_icon_build121.png'));

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
      expect(px[0], inInclusiveRange(0, 40));
      expect(px[1], inInclusiveRange(0, 40));
      expect(px[2], inInclusiveRange(0, 40));
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
      expect(px[0], inInclusiveRange(188, 214));
      expect(px[1], inInclusiveRange(156, 180));
      expect(px[2], inInclusiveRange(116, 135));

      // Guard against the pale Build 120 gold treatment.
      expect(px[0], lessThanOrEqualTo(214));
      expect(px[1], lessThanOrEqualTo(180));
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

  test(
      'iOS AppIcon set exists and Contents.json is valid with 1024 marketing icon',
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
  });
}
