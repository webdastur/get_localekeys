import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:pretty_json/pretty_json.dart';

void main(List<String> args) {
  if (_isHelpCommand(args)) {
    _printHelperDisplay();
  } else {
    handleLangFiles(_generateOption(args));
  }
}

bool _isHelpCommand(List<String> args) {
  return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
}

void _printHelperDisplay() {
  var parser = _generateArgParser(null);
  print(parser.usage);
}

GenerateOptions _generateOption(List<String> args) {
  var generateOptions = GenerateOptions();
  var parser = _generateArgParser(generateOptions);
  parser.parse(args);
  return generateOptions;
}

ArgParser _generateArgParser(GenerateOptions generateOptions) {
  var parser = ArgParser();

  parser.addOption(
    'source-dir',
    abbr: 'S',
    defaultsTo: 'assets/langs',
    callback: (String x) => generateOptions.sourceDir = x,
    help: 'Folder containing localization files',
  );

  parser.addOption(
    'source-file',
    abbr: 's',
    callback: (String x) => generateOptions.sourceFile = x,
    help: 'File to use for localization',
  );

  parser.addOption('output-dir',
      abbr: 'O',
      defaultsTo: 'lib/generated',
      callback: (String x) => generateOptions.outputDir = x,
      help: 'Output folder stores for the generated file');

  parser.addOption(
    'output-file',
    abbr: 'o',
    defaultsTo: 'locale_keys.dart',
    callback: (String x) => generateOptions.outputFile = x,
    help: 'Output file name',
  );

  parser.addOption(
    'output-message-file',
    abbr: 'm',
    defaultsTo: 'app_messages.dart',
    callback: (String x) => generateOptions.outputMessageFile = x,
    help: 'Output Messages file name',
  );

  return parser;
}

class GenerateOptions {
  String sourceDir;
  String sourceFile;
  String templateLocale;
  String outputDir;
  String outputFile;
  String outputMessageFile;

  @override
  String toString() {
    return 'sourceDir: $sourceDir sourceFile: $sourceFile outputDir: $outputDir outputFile: $outputFile';
  }
}

void handleLangFiles(GenerateOptions options) async {
  final current = Directory.current;
  final source = Directory.fromUri(Uri.parse(options.sourceDir));
  final output = Directory.fromUri(Uri.parse(options.outputDir));
  final sourcePath = Directory(path.join(current.path, source.path));
  final outputPath = Directory(path.join(current.path, output.path, options.outputFile));
  final outputMessagesPath = Directory(path.join(current.path, output.path, options.outputMessageFile));

  if (!await sourcePath.exists()) {
    printError('Source path does not exist');
    return;
  }

  var files = await dirContents(sourcePath);
  if (options.sourceFile != null) {
    final sourceFile = File(path.join(source.path, options.sourceFile));
    if (!await sourceFile.exists()) {
      printError('Source file does not exist (${sourceFile.toString()})');
      return;
    }
    files = [sourceFile];
  } else {
    //filtering format
    files = files.where((f) => f.path.contains('.json')).toList();
  }

  if (files.isNotEmpty) {
    generateFile(files, outputPath, outputMessagesPath);
  } else {
    printError('Source path empty');
  }
}

Future<List<FileSystemEntity>> dirContents(Directory dir) {
  var files = <FileSystemEntity>[];
  var completer = Completer<List<FileSystemEntity>>();
  var lister = dir.list(recursive: false);
  lister.listen((file) => files.add(file), onDone: () => completer.complete(files));
  return completer.future;
}

void generateFile(List<FileSystemEntity> files, Directory outputPath, Directory outputMessagesPath) async {
  var generatedFile = File(outputPath.path);
  var generatedMessagesFile = File(outputMessagesPath.path);
  if (!generatedFile.existsSync()) {
    generatedFile.createSync(recursive: true);
  }
  if (!generatedMessagesFile.existsSync()) {
    generatedMessagesFile.createSync(recursive: true);
  }

  var classBuilder = StringBuffer();

  await _writeKeys(classBuilder, files);
  var data = await _writeMessages(files);

  classBuilder.writeln('}');
  generatedMessagesFile.writeAsStringSync(data);
  generatedFile.writeAsStringSync(classBuilder.toString());

  printInfo('All done! File generated in ${outputPath.path}');
  printInfo('All done! File generated in ${generatedMessagesFile.path}');
}

Future<String> _writeMessages(List<FileSystemEntity> files) async {
  Map<String, Map<String, String>> data = {};
  for (int i = 0; i < files.length; i++) {
    var element = files[i];
    var fileData = File(element.path);
    String name = path.basename(fileData.path).split(".json")[0];
    var jsonData = jsonDecode(await fileData.readAsString());
    Map<String, String> json = Map<String, String>();
    jsonData.forEach((k, v) => json[k] = v.toString());
    data[name] = json;
  }
  return '''
import 'package:get/get.dart';

class AppMessages extends Translations {
  @override
  Map<String, Map<String, String>> get keys => ${prettyJson(data)};
}
  ''';
}

Future _writeKeys(StringBuffer classBuilder, List<FileSystemEntity> files) async {
  var file = '''
// DO NOT EDIT. This is code generated via package:get_localekeys/get_localekeys.dart
abstract class  LocaleKeys {
''';

  final fileData = File(files.first.path);

  Map<String, dynamic> translations = json.decode(await fileData.readAsString());

  file += _resolve(translations);

  classBuilder.writeln(file);
}

String _resolve(Map<String, dynamic> translations, [String accKey]) {
  var fileContent = '';

  final sortedKeys = translations.keys.toList();

  for (var key in sortedKeys) {
    if (translations[key] is Map) {
      var nextAccKey = key;
      if (accKey != null) {
        nextAccKey = '$accKey.$key';
      }

      fileContent += _resolve(translations[key], nextAccKey);
    }

    accKey != null
        ? fileContent += '  static const ${accKey.replaceAll('.', '_')}\_$key = \'$accKey.$key\';\n'
        : fileContent += '  static const $key = \'$key\';\n';
  }

  return fileContent;
}

void printInfo(String info) {
  print('\u001b[32mget_localekeys: $info\u001b[0m');
}

void printError(String error) {
  print('\u001b[31m[ERROR] get_localekeys: $error\u001b[0m');
}
