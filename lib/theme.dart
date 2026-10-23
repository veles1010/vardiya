import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themePreferenceKey = 'vardiya.settings.theme.v1';

Future<ThemeMode> loadThemePreference() async {
  try {
    final saved = await SharedPreferencesAsync().getString(themePreferenceKey);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.dark,
    );
  } catch (_) {
    return ThemeMode.dark;
  }
}

ThemeData vardiyaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff176b5d),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xff80d7bc) : const Color(0xff176b5d),
        onPrimary: dark ? const Color(0xff00382c) : Colors.white,
        surface: dark ? const Color(0xff191e22) : const Color(0xfff5f7f8),
        surfaceContainerLow: dark ? const Color(0xff22292e) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xff293238)
            : const Color(0xffedf2f3),
        surfaceContainerHigh: dark
            ? const Color(0xff303b41)
            : const Color(0xffe5ecee),
        surfaceContainerHighest: dark
            ? const Color(0xff37434a)
            : const Color(0xffdce5e7),
        onSurface: dark ? const Color(0xffe3e9ec) : const Color(0xff263746),
        onSurfaceVariant: dark
            ? const Color(0xffb7c6cc)
            : const Color(0xff475563),
        outline: dark ? const Color(0xff879aa3) : const Color(0xff657b85),
        outlineVariant: dark
            ? const Color(0xff46565e)
            : const Color(0xffccd7da),
        tertiaryContainer: dark
            ? const Color(0xff49391e)
            : const Color(0xfffff0d8),
        onTertiaryContainer: dark
            ? const Color(0xffffdfaa)
            : const Color(0xff715019),
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'VardiyaSans',
    colorScheme: scheme,
  );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      bodySmall: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
      bodyMedium: TextStyle(fontSize: 15, color: scheme.onSurface),
    ),
    dividerColor: scheme.outlineVariant,
    disabledColor: scheme.onSurface.withValues(alpha: .5),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
      floatingLabelStyle: TextStyle(color: scheme.primary),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      counterStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      errorStyle: TextStyle(
        color: scheme.error,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      errorMaxLines: 4,
      border: border(scheme.outline),
      enabledBorder: border(scheme.outline),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      disabledBorder: border(scheme.outlineVariant),
    ),
  );
}

class ThemeToolbar extends StatelessWidget {
  const ThemeToolbar({
    super.key,
    required this.mode,
    required this.onChanged,
    this.saveFailed = false,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  final bool saveFailed;
  @override
  Widget build(BuildContext context) {
    final menu = MenuController();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Vardiya',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (saveFailed)
                Tooltip(
                  message: 'Tema bu cihazda kaydedilemedi. Depolama iznini kontrol edin.',
                  child: Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              MenuAnchor(
                controller: menu,
                menuChildren:
                    const [ThemeMode.light, ThemeMode.dark, ThemeMode.system]
                        .map(
                          (m) => MenuItemButton(
                            leadingIcon: Icon(
                              mode == m ? Icons.check : Icons.circle_outlined,
                              size: 18,
                            ),
                            onPressed: () {
                              menu.close();
                              onChanged(m);
                            },
                            child: Text(themeLabel(m)),
                          ),
                        )
                        .toList(),
                builder: (context, controller, child) => IconButton(
                  tooltip: 'Tema seçimi · ${themeLabel(mode)}',
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  icon: Icon(switch (mode) {
                    ThemeMode.dark => Icons.dark_mode_outlined,
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.system => Icons.brightness_auto_outlined,
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => 'Koyu',
  ThemeMode.light => 'Açık',
  ThemeMode.system => 'Sistem',
};
