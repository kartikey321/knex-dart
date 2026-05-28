// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const _agents = {
  'antigravity': '.agents',
  'cursor': '.cursor',
  'claude-code': '.claude',
  'cline': '.cline',
  'codex': '.agents',
  'copilot': '.github',
  'command-code': '.commandcode',
  'opencode': '.opencode',
  'continue': '.continue',
  'windsurf': '.windsurf',
  'general': '.agents',
};

void main(List<String> args) {
  String? requestedAgent;
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--agent' || args[i] == '-a') && i + 1 < args.length) {
      requestedAgent = args[++i];
    } else if (args[i].startsWith('--agent=')) {
      requestedAgent = args[i].substring('--agent='.length);
    } else if (args[i] == '--help' || args[i] == '-h') {
      _printHelp();
      exit(0);
    }
  }

  if (requestedAgent != null && !_agents.containsKey(requestedAgent)) {
    print('Error: Unknown agent "$requestedAgent".');
    print('Valid agents: ${_agents.keys.join(', ')}');
    exit(1);
  }

  // Locate package_config.json walking up from cwd
  final packageConfigFile = _findPackageConfig();
  if (packageConfigFile == null) {
    print('Error: Could not find .dart_tool/package_config.json.');
    print('Run "dart pub get" first.');
    exit(1);
  }

  // Resolve knex_dart package root from package_config
  final config = jsonDecode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = (config['packages'] as List<dynamic>?) ?? [];
  final knexEntry = packages
      .whereType<Map<String, dynamic>>()
      .where((p) => p['name'] == 'knex_dart')
      .firstOrNull;

  if (knexEntry == null) {
    print('Error: "knex_dart" not found in package_config.json.');
    exit(1);
  }

  final rootUri = knexEntry['rootUri'] as String;
  final knexPath = _resolveUri(rootUri, packageConfigFile.parent.path);
  final skillsSource = Directory('$knexPath/skills');

  if (!skillsSource.existsSync()) {
    print('Error: skills directory not found at ${skillsSource.path}');
    exit(1);
  }

  // Auto-detect or use requested agent directory
  String? targetDirName;
  if (requestedAgent != null) {
    targetDirName = _agents[requestedAgent]!;
  } else {
    for (final entry in _agents.entries) {
      if (Directory('${entry.value}/skills').existsSync()) {
        targetDirName = entry.value;
        print('Auto-detected agent directory: ${entry.value}/skills');
        break;
      }
    }
  }

  if (targetDirName == null) {
    print('Could not auto-detect an agent directory.');
    print('Specify one with --agent: ${_agents.keys.join(', ')}');
    exit(1);
  }

  // Copy skills, skipping those already at the current version
  final targetBase = Directory('$targetDirName/skills');
  targetBase.createSync(recursive: true);

  var updated = false;
  for (final entry in skillsSource.listSync().whereType<Directory>()) {
    final skillName = entry.path.split(Platform.pathSeparator).last;
    final skillFile = File('${entry.path}${Platform.pathSeparator}SKILL.md');
    if (!skillFile.existsSync()) continue;

    final sourceVersion = _getSkillVersion(skillFile);
    final targetDir = Directory('${targetBase.path}${Platform.pathSeparator}$skillName');
    final targetFile = File('${targetDir.path}${Platform.pathSeparator}SKILL.md');

    if (targetFile.existsSync()) {
      final targetVersion = _getSkillVersion(targetFile);
      if (sourceVersion != null && sourceVersion == targetVersion) continue;
      print('Updating skill "$skillName" to version $sourceVersion...');
      targetDir.deleteSync(recursive: true);
    } else {
      print('Adding skill "$skillName" (version $sourceVersion)...');
    }

    _copyDirectory(entry, targetDir);
    updated = true;
  }

  if (!updated) {
    print('All knex_dart skills are already up to date.');
  }
}

String? _getSkillVersion(File skillFile) {
  try {
    final content = skillFile.readAsStringSync();
    final match = RegExp(r'knex_dart_version:\s*([\w.+\-]+)').firstMatch(content);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}

File? _findPackageConfig() {
  var dir = Directory.current;
  while (true) {
    final candidate = File(
      '${dir.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
    );
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

String _resolveUri(String uri, String basePath) {
  if (uri.startsWith('file://')) return Uri.parse(uri).toFilePath();
  if (uri.startsWith('/') || (uri.length > 1 && uri[1] == ':')) return uri; // absolute
  return '$basePath${Platform.pathSeparator}$uri';
}

void _copyDirectory(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final name = entity.path.split(Platform.pathSeparator).last;
    final targetPath = '${target.path}${Platform.pathSeparator}$name';
    if (entity is File) {
      entity.copySync(targetPath);
    } else if (entity is Directory) {
      _copyDirectory(entity, Directory(targetPath));
    }
  }
}

void _printHelp() {
  print('knex_dart install-skills');
  print('');
  print('Installs knex_dart agent skills into your project.');
  print('');
  print('Usage:');
  print('  dart run knex_dart:install_skills [--agent <name>]');
  print('');
  print('Options:');
  print('  -a, --agent   Agent to install for (auto-detected if omitted)');
  print('  -h, --help    Show this help');
  print('');
  print('Supported agents:');
  for (final entry in _agents.entries) {
    print('  ${entry.key.padRight(16)} → ${entry.value}/skills/');
  }
}
