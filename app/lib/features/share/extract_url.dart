/// Instagram/Facebook's share sheet often sends shared text with extra
/// wording around the link (e.g. "Check this out! https://..."), so pull
/// just the URL out of it.
String? extractUrl(String text) {
  final match = RegExp(r'https?://\S+').firstMatch(text);
  return match?.group(0);
}
