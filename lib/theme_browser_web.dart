import 'package:web/web.dart' as web;

void syncBrowserTheme(bool dark) {
  web.document.documentElement?.setAttribute(
    'data-theme',
    dark ? 'dark' : 'light',
  );
  web.document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute('content', dark ? '#191e22' : '#f5f7f8');
}
