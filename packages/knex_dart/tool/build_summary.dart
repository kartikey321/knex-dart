// Build an analyzer summary bundle for knex_dart, in the format the
// in-browser dart-live analyzer consumes via dartLivePackages[].summaryUrl.
//
// Usage:
//   dart run tool/build_summary.dart <package-dir> <out.sum>
//
// Run `dart pub get` in the package directory first.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/driver_based_analysis_context.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/build_summary.dart <package-dir> <out.sum>');
    exit(64);
  }
  final pkgDir = Directory(args[0]).absolute.resolveSymbolicLinksSync();
  final outPath = args[1];

  final pubspec = loadYaml(
    await File('$pkgDir/pubspec.yaml').readAsString(),
  ) as YamlMap;
  final pkgName = pubspec['name'] as String;

  final libDir = Directory('$pkgDir/lib');
  final libDirPath = libDir.uri.path;
  final libUris = <Uri>[
    for (final e in libDir.listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart'))
        Uri.parse('package:$pkgName/${e.uri.path.substring(libDirPath.length)}'),
  ];
  if (libUris.isEmpty) {
    stderr.writeln('no public libraries found under $pkgDir/lib');
    exit(1);
  }

  final collection = AnalysisContextCollection(
    includedPaths: [pkgDir],
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );
  final ctx = collection.contextFor(pkgDir) as DriverBasedAnalysisContext;
  final bytes = await ctx.driver.buildPackageBundle(uriList: libUris);
  await File(outPath).writeAsBytes(bytes);
  stdout.writeln('wrote ${bytes.length} bytes to $outPath '
      '(${libUris.length} libraries)');
}
