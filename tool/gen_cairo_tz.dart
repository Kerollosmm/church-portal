// Generates `lib/domain/cairo_tzdata.dart` containing only the `Africa/Cairo`
// tzdb record extracted from `package:timezone/data/latest_10y.dart`.
//
// Usage:
//   dart run tool/gen_cairo_tz.dart          # regenerate lib/domain/cairo_tzdata.dart
//   dart run tool/gen_cairo_tz.dart --check  # exit 1 if generated file is out of date

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _outPath = 'lib/domain/cairo_tzdata.dart';
const _targetZone = 'Africa/Cairo';

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final latest10yFile = _resolveLatest10yFile();
  final source = latest10yFile.readAsStringSync();

  final versionMatch = RegExp(r'// Timezone data version:\s*(\S+)').firstMatch(source);
  final tzVersion = versionMatch?.group(1) ?? 'unknown';

  final allBytes = _decodeEmbeddedData(source);
  final cairoChunk = _extractLocationChunk(allBytes, _targetZone);

  // Cross-verify against full latest_10y database before writing anything.
  tzdata.initializeTimeZones();
  final expected = tz.getLocation(_targetZone);

  tz.initializeDatabase(Uint8List.fromList(cairoChunk));
  final actual = tz.getLocation(_targetZone);
  _assertLocationEqual(expected, actual);

  final generated = _formatDartFile(cairoChunk, tzVersion);
  final outFile = File(_outPath);
  if (checkOnly) {
    if (!outFile.existsSync() || outFile.readAsStringSync() != generated) {
      stderr.writeln('$_outPath is out of date. Run: dart run tool/gen_cairo_tz.dart');
      exitCode = 1;
    } else {
      stdout.writeln('$_outPath OK (tzdb $tzVersion, ${cairoChunk.length} B)');
    }
    return;
  }

  outFile.writeAsStringSync(generated);
  stdout.writeln('Generated $_outPath (${cairoChunk.length} B from tzdb $tzVersion)');
}

File _resolveLatest10yFile() {
  final cfgFile = File('.dart_tool/package_config.json');
  if (!cfgFile.existsSync()) {
    throw StateError('Missing .dart_tool/package_config.json — run `flutter pub get` first.');
  }
  final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = (cfg['packages'] as List).cast<Map<String, dynamic>>();
  final tzPkg = packages.firstWhere(
    (p) => p['name'] == 'timezone',
    orElse: () => throw StateError('Package `timezone` not found in .dart_tool/package_config.json.'),
  );
  final rootUri = Uri.parse(tzPkg['rootUri'] as String);
  final pkgRoot = rootUri.isAbsolute
      ? Directory.fromUri(rootUri)
      : Directory.fromUri(cfgFile.uri.resolveUri(rootUri));
  final latest = File.fromUri(pkgRoot.uri.resolve('lib/data/latest_10y.dart'));
  if (!latest.existsSync()) {
    throw StateError('Could not locate ${latest.path}');
  }
  return latest;
}

Uint8List _decodeEmbeddedData(String dartSource) {
  final declMatch = RegExp(r'const _embeddedData\s*=\s*(.*?);', dotAll: true).firstMatch(dartSource);
  if (declMatch == null) {
    throw const FormatException('Could not locate _embeddedData in latest_10y.dart');
  }
  final body = declMatch.group(1)!;
  final bytes = <int>[];
  final strLit = RegExp(r"'([^']*)'");
  for (final m in strLit.allMatches(body)) {
    final s = m.group(1)!;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch != r'\') {
        bytes.add(ch.codeUnitAt(0));
        continue;
      }
      if (i + 1 >= s.length) throw const FormatException('Trailing backslash in _embeddedData');
      final next = s[++i];
      switch (next) {
        case 'x':
          final hex = s.substring(i + 1, i + 3);
          bytes.add(int.parse(hex, radix: 16));
          i += 2;
        case 'n':
          bytes.add(0x0a);
        case 'r':
          bytes.add(0x0d);
        case 't':
          bytes.add(0x09);
        case 'b':
          bytes.add(0x08);
        case 'f':
          bytes.add(0x0c);
        case 'v':
          bytes.add(0x0b);
        case r'\':
          bytes.add(0x5c);
        case "'":
          bytes.add(0x27);
        case r'$':
          bytes.add(0x24);
        default:
          throw FormatException('Unsupported escape \\$next in _embeddedData');
      }
    }
  }
  return Uint8List.fromList(bytes);
}

Uint8List _extractLocationChunk(Uint8List raw, String targetName) {
  final bd = ByteData.sublistView(raw);
  var offset = 0;
  while (offset < raw.length) {
    if (raw.length - offset < 8) {
      throw FormatException('Truncated tzdb header at $offset');
    }
    final length = bd.getUint32(offset);
    if (length % 8 != 0 || offset + 8 + length > raw.length) {
      throw FormatException('Invalid tzdb chunk length $length at $offset');
    }
    final chunk = Uint8List.sublistView(raw, offset, offset + 8 + length);
    tz.initializeDatabase(chunk);
    if (tz.timeZoneDatabase.locations.containsKey(targetName)) {
      return Uint8List.fromList(chunk);
    }
    offset += 8 + length;
  }
  throw StateError('Location "$targetName" not found in latest_10y.dart');
}

void _assertLocationEqual(tz.Location expected, tz.Location actual) {
  if (expected.name != actual.name) {
    throw StateError('Location name mismatch: ${actual.name} != ${expected.name}');
  }
  if (expected.transitionAt.length != actual.transitionAt.length) {
    throw StateError('Transition count mismatch');
  }
  for (var i = 0; i < expected.transitionAt.length; i++) {
    if (expected.transitionAt[i] != actual.transitionAt[i] ||
        expected.transitionZone[i] != actual.transitionZone[i]) {
      throw StateError('Transition mismatch at index $i');
    }
  }
  if (expected.zones.length != actual.zones.length) {
    throw StateError('Zone count mismatch');
  }
  for (var i = 0; i < expected.zones.length; i++) {
    final ez = expected.zones[i];
    final az = actual.zones[i];
    if (ez.offset != az.offset || ez.isDst != az.isDst || ez.abbreviation != az.abbreviation) {
      throw StateError('Zone mismatch at index $i');
    }
  }
}

String _formatDartFile(Uint8List chunk, String tzVersion) {
  final buf = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT BY HAND.')
    ..writeln('// Regenerate with: dart run tool/gen_cairo_tz.dart')
    ..writeln('// Source: package:timezone/data/latest_10y.dart (tzdb $tzVersion)')
    ..writeln()
    ..writeln("const String cairoTzVersion = '$tzVersion';")
    ..writeln()
    ..writeln('const List<int> cairoTzData = <int>[');
  for (var i = 0; i < chunk.length; i += 16) {
    final end = (i + 16 < chunk.length) ? i + 16 : chunk.length;
    final slice = chunk.sublist(i, end).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
    buf.writeln('  $slice,');
  }
  buf.writeln('];');
  return buf.toString();
}
