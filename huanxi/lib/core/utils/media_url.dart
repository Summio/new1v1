import '../constants/app_constants.dart';

String toAbsoluteMediaUrl(String? raw) {
  if (raw == null) return '';
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  if (!value.startsWith('/')) return value;

  final api = Uri.tryParse(AppConstants.apiBaseUrl);
  if (api == null || api.host.isEmpty) return value;
  final origin = api.hasPort
      ? '${api.scheme}://${api.host}:${api.port}'
      : '${api.scheme}://${api.host}';
  return '$origin$value';
}

List<String> normalizeMediaList(dynamic value) {
  if (value is! List) return const [];
  final out = <String>[];
  final seen = <String>{};
  for (final item in value) {
    if (item is! String) continue;
    final url = toAbsoluteMediaUrl(item);
    if (url.isEmpty || seen.contains(url)) continue;
    seen.add(url);
    out.add(url);
  }
  return out;
}
