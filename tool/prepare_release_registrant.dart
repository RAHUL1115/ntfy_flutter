import 'dart:io';

void main() {
  final file = File(
    'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
  );
  final lines = file.readAsLinesSync();
  final plugin = lines.indexWhere(
    (line) => line.contains(
      'dev.flutter.plugins.integration_test.IntegrationTestPlugin()',
    ),
  );
  if (plugin < 1 || plugin + 3 >= lines.length) {
    stderr.writeln('integration_test registrant block not found');
    exitCode = 1;
    return;
  }
  lines.removeRange(plugin - 1, plugin + 4);
  file.writeAsStringSync(
    '${lines.join(Platform.lineTerminator)}${Platform.lineTerminator}',
  );
}
