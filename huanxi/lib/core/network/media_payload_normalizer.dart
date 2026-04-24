import '../utils/media_url.dart';

const Set<String> _mediaStringKeySet = <String>{
  'avatar',
  'cover',
  'coverurl',
  'image',
  'imageurl',
  'faceurl',
  'peeravatar',
};

const Set<String> _mediaListKeySet = <String>{
  'albumphotos',
  'photos',
  'images',
};

String _normalizeKey(String key) {
  return key.replaceAll('_', '').replaceAll('-', '').toLowerCase();
}

bool _isMediaStringKey(String key) => _mediaStringKeySet.contains(_normalizeKey(key));

bool _isMediaListKey(String key) => _mediaListKeySet.contains(_normalizeKey(key));

bool _looksLikeUploadPath(String value) => value.trim().startsWith('/uploads/');

dynamic normalizeMediaPayload(dynamic value, {String? parentKey}) {
  if (value is Map<String, dynamic>) {
    final out = <String, dynamic>{};
    value.forEach((key, item) {
      out[key] = normalizeMediaPayload(item, parentKey: key);
    });
    return out;
  }

  if (value is List) {
    if (parentKey != null && _isMediaListKey(parentKey)) {
      return normalizeMediaList(value);
    }
    return value.map((item) => normalizeMediaPayload(item, parentKey: parentKey)).toList();
  }

  if (value is String) {
    if ((parentKey != null && _isMediaStringKey(parentKey)) || _looksLikeUploadPath(value)) {
      return toAbsoluteMediaUrl(value);
    }
  }
  return value;
}
