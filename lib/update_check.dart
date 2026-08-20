import 'dart:convert';
import 'dart:io';

const latestReleaseApi =
    'https://api.github.com/repos/RAHUL1115/ntfy_flutter/releases/latest';

Future<({String version, Uri url})> fetchLatestRelease() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(latestReleaseApi));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set('X-GitHub-Api-Version', '2022-11-28')
      ..set(HttpHeaders.userAgentHeader, 'ntfy-flutter');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GitHub returned ${response.statusCode}.');
    }
    final json = jsonDecode(await utf8.decodeStream(response));
    if (json case {
      'tag_name': final String tag,
      'html_url': final String url,
    }) {
      return (
        version: tag.replaceFirst(RegExp(r'^v'), ''),
        url: Uri.parse(url),
      );
    }
    throw const FormatException('GitHub returned an invalid release.');
  } finally {
    client.close(force: true);
  }
}

bool isNewerRelease(String latest, String current) {
  final latestParts = _versionParts(latest);
  final currentParts = _versionParts(current);
  for (var index = 0; index < latestParts.length; index++) {
    if (latestParts[index] != currentParts[index]) {
      return latestParts[index] > currentParts[index];
    }
  }
  return false;
}

List<int> _versionParts(String value) {
  final parts = value.split('+').first.split('-').first.split('.');
  if (parts.isEmpty || parts.any((part) => int.tryParse(part) == null)) {
    throw FormatException('Invalid app version: $value');
  }
  return [
    for (var index = 0; index < 3; index++)
      index < parts.length ? int.parse(parts[index]) : 0,
  ];
}
