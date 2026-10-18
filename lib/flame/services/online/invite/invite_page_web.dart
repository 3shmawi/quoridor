import 'package:web/web.dart' as web;

/// The address this page was opened at.
Uri? currentPage() => Uri.base;

/// Takes the invite back out of the address, so reloading the page does not
/// try to join the same game again.
void forgetInviteInPage() {
  final page = Uri.base;
  if (!page.queryParameters.containsKey('join')) return;
  final rest = Map.of(page.queryParameters)..remove('join');
  final clean = page.replace(queryParameters: rest.isEmpty ? null : rest);
  var text = clean.toString();
  // An empty query leaves a bare '?' behind.
  if (rest.isEmpty && text.contains('?')) {
    final hash = clean.hasFragment ? '#${clean.fragment}' : '';
    text = '${clean.scheme}://${clean.authority}${clean.path}$hash';
  }
  web.window.history.replaceState(null, '', text);
}
