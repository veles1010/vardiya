import 'package:web/web.dart' as web;

void clearCallbackUrl() {
  final uri = Uri.base;
  web.window.history.replaceState(
    null,
    '',
    uri.replace(query: '', fragment: '').toString(),
  );
}
