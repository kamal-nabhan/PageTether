// One-off generator that turns the raw designer PNGs (PageTether_Icon.png
// and PageTether_Icon-removebg-preview.png, historically dropped in the repo
// root) into the small, launcher-icons-ready assets committed under
// assets/icon/.
//
// Usage (from repo root):
//   dart run tool/generate_icons.dart
//
// Not part of the app or its test suite — lives under tool/ on purpose so
// `flutter test` never picks it up.
import 'dart:io';

import 'package:image/image.dart' as img;

const _canvasSize = 1024;
// Android adaptive icons only guarantee the inner ~66% of the foreground
// layer survives masking on every launcher shape. Keep the logo comfortably
// inside that so nothing gets clipped.
const _safeZoneFraction = 0.62;

void main(List<String> args) {
  final repoRoot = Directory.current.path;

  _generateMainIcon(
    srcPath: '$repoRoot/PageTether_Icon.png',
    outPath: '$repoRoot/assets/icon/pagetether_icon.png',
  );

  _generateForegroundIcon(
    srcPath: '$repoRoot/PageTether_Icon-removebg-preview.png',
    outPath: '$repoRoot/assets/icon/pagetether_icon_foreground.png',
  );

  stdout.writeln('Done. Generated assets/icon/pagetether_icon.png '
      'and assets/icon/pagetether_icon_foreground.png.');
}

void _generateMainIcon({required String srcPath, required String outPath}) {
  final bytes = File(srcPath).readAsBytesSync();
  final src = img.decodePng(bytes);
  if (src == null) {
    throw StateError('Could not decode $srcPath as PNG');
  }

  stdout.writeln('Main icon source: ${src.width}x${src.height}, '
      'hasAlpha=${src.hasAlpha}');

  // Pad to square (centered) if the source isn't already square, using the
  // source's own background color sampled from its corner.
  final side = src.width > src.height ? src.width : src.height;
  img.Image square = src;
  if (src.width != src.height) {
    final bgPixel = src.getPixel(0, 0);
    final bg = img.ColorRgb8(
      bgPixel.r.toInt(),
      bgPixel.g.toInt(),
      bgPixel.b.toInt(),
    );
    square = img.Image(width: side, height: side, numChannels: 3);
    img.fill(square, color: bg);
    img.compositeImage(
      square,
      src,
      dstX: (side - src.width) ~/ 2,
      dstY: (side - src.height) ~/ 2,
    );
  }

  // Downscale to the target size.
  final resized = img.copyResize(
    square,
    width: _canvasSize,
    height: _canvasSize,
    interpolation: img.Interpolation.average,
  );

  // Flatten onto an opaque RGB canvas so there's no alpha channel at all —
  // iOS requires a fully opaque app icon.
  final opaque = img.Image(
    width: _canvasSize,
    height: _canvasSize,
    numChannels: 3,
  );
  final corner = resized.getPixel(0, 0);
  final bgColor = img.ColorRgb8(
    corner.r.toInt(),
    corner.g.toInt(),
    corner.b.toInt(),
  );
  img.fill(opaque, color: bgColor);
  img.compositeImage(opaque, resized);

  File(outPath).parent.createSync(recursive: true);
  File(outPath).writeAsBytesSync(img.encodePng(opaque));
  stdout.writeln('Wrote $outPath (${opaque.width}x${opaque.height}, '
      'hasAlpha=${opaque.hasAlpha})');
}

void _generateForegroundIcon({required String srcPath, required String outPath}) {
  final bytes = File(srcPath).readAsBytesSync();
  final src = img.decodePng(bytes);
  if (src == null) {
    throw StateError('Could not decode $srcPath as PNG');
  }

  stdout.writeln('Foreground source: ${src.width}x${src.height}, '
      'hasAlpha=${src.hasAlpha}');

  // Trim to the logo's actual (non-transparent) bounding box so we control
  // padding precisely, then scale it down to fit inside the adaptive-icon
  // safe zone and paste it centered on a transparent 1024x1024 canvas.
  final trimmed = img.trim(src, mode: img.TrimMode.transparent);

  final targetContentSize = (_canvasSize * _safeZoneFraction).round();
  final scale = targetContentSize /
      (trimmed.width > trimmed.height ? trimmed.width : trimmed.height);
  final contentWidth = (trimmed.width * scale).round();
  final contentHeight = (trimmed.height * scale).round();

  final scaledContent = img.copyResize(
    trimmed,
    width: contentWidth,
    height: contentHeight,
    interpolation: img.Interpolation.average,
  );

  final canvas = img.Image(
    width: _canvasSize,
    height: _canvasSize,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(
    canvas,
    scaledContent,
    dstX: (_canvasSize - contentWidth) ~/ 2,
    dstY: (_canvasSize - contentHeight) ~/ 2,
  );

  File(outPath).parent.createSync(recursive: true);
  File(outPath).writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Wrote $outPath (${canvas.width}x${canvas.height}, '
      'content ${contentWidth}x$contentHeight, hasAlpha=${canvas.hasAlpha})');
}
