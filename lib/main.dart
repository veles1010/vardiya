import 'dart:async';

import 'account/account_service.dart';
import 'account/account_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data.dart';
import 'domain.dart';
import 'editors.dart';
import 'widgets.dart';
import 'theme.dart';
import 'theme_browser.dart'
    if (dart.library.js_interop) 'theme_browser_web.dart';

import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeMode = await loadThemePreference();
  const config = CloudConfig();
  final account = AccountController(SupabaseAccountGateway(config));
  if (config.valid) {
    unawaited(account.start());
  }
  runApp(
    VardiyaApp(
      store: ScheduleStore(LocalScheduleRepository()),
      account: account,
      config: config,
      initialThemeMode: themeMode,
    ),
  );
}

class VardiyaApp extends StatefulWidget {
  const VardiyaApp({
    super.key,
    required this.store,
    this.initialized = false,
    this.initialThemeMode = ThemeMode.dark,
    this.account,
    this.config = const CloudConfig(),
  });
  final ScheduleStore store;
  final AccountController? account;
  final CloudConfig config;
  final bool initialized;
  final ThemeMode initialThemeMode;
  @override
  State<VardiyaApp> createState() => _VardiyaAppState();
}

class _VardiyaAppState extends State<VardiyaApp> {
  late ThemeMode mode = widget.initialThemeMode;
  bool saveFailed = false;
  Future<void> saving = Future.value();
  void changeTheme(ThemeMode next) {
    setState(() {
      mode = next;
      saveFailed = false;
    });
    saving = saving
        .then(
          (_) =>
              SharedPreferencesAsync().setString(themePreferenceKey, next.name),
        )
        .then((_) {
          if (mounted) setState(() => saveFailed = false);
        })
        .catchError((Object _) {
          if (mounted) setState(() => saveFailed = true);
        });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vardiya',
    debugShowCheckedModeBanner: false,
    locale: const Locale('tr', 'TR'),
    supportedLocales: const [Locale('tr', 'TR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: vardiyaTheme(Brightness.light),
    darkTheme: vardiyaTheme(Brightness.dark),
    themeMode: mode,
    builder: (context, child) {
      syncBrowserTheme(Theme.of(context).brightness == Brightness.dark);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: Overlay.wrap(
          child: Column(
            // Paint the persistent toolbar after Navigator's modal semantics barrier.
            verticalDirection: VerticalDirection.up,
            children: [
              Expanded(child: child!),
              ThemeToolbar(
                mode: mode,
                onChanged: changeTheme,
                saveFailed: saveFailed,
              ),
            ],
          ),
        ),
      );
    },
    home: widget.account == null
        ? (widget.initialized
              ? HomeScreen(store: widget.store)
              : _Bootstrap(store: widget.store))
        : WorkspaceShell(
            controller: widget.account!,
            config: widget.config,
            demo: widget.initialized
                ? HomeScreen(store: widget.store)
                : _Bootstrap(store: widget.store),
          ),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.store});
  final ScheduleStore store;
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<void> loading = widget.store.initialize();
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storage_outlined, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      'Yerel veriler açılamadı. Tarayıcı depolama iznini kontrol edin. Kayıtlı verilerinizin üzerine yazılmadı.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () =>
                          setState(() => loading = widget.store.initialize()),
                      child: Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return HomeScreen(store: widget.store);
    },
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int mode = 0, managerTab = 0;
  DateTime month = monthOf(DateTime.now()),
      selected = dayOf(DateTime.now()),
      week = weekOf(DateTime.now());
  String? teamId, employeeId;
  ScheduleStore get store => widget.store;
  AppData get data => store.data;
  String get currentTeam => teamId ?? data.teams.first.id;
  String? get currentEmployee =>
      employeeId ?? (data.employees.isEmpty ? null : data.employees.first.id);
  @override
  void initState() {
    super.initState();
    store.addListener(refresh);
  }

  @override
  void dispose() {
    store.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> perform(Future<void> Function() task, String success) async {
    try {
      await task();
      if (mounted) {
        message(success);
      }
    } catch (e) {
      if (mounted) {
        message(errorText(e));
      }
    }
  }

  Future<void> editShift({Shift? shift, String? person, DateTime? date}) =>
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShiftEditor(
          store: store,
          date: date ?? selected,
          shift: shift,
          personal: mode == 0,
          teamId: mode == 1 ? currentTeam : null,
          employeeId: person,
        ),
      );
  Future<void> removeShift(Shift shift) async {
    final personal = mode == 0;
    if (await confirmAction(
      context,
      'Kaydı sil',
      '“${shift.label}” kaydı ${personal ? 'kişisel takviminizden' : 'taslaktan'} silinsin mi?${personal ? '' : ' Yayımlanmış kopya yeniden yayımlanana kadar korunur.'}',
      'Sil',
    )) {
      await perform(
        () => store.deleteShift(shift.id, personal: personal),
        'Kayıt silindi.',
      );
    }
  }

  void editTeam([Team? team]) => showDialog(
    context: context,
    builder: (_) => NameEditor(
      title: team == null ? 'Yeni ekip' : 'Ekip adını düzenle',
      initial: team?.name ?? '',
      onSave: (name, role, active) async {
        final id = team?.id ?? newId();
        await store.saveTeam(Team(id: id, name: name));
        if (mounted) {
          setState(() => teamId = id);
        }
      },
    ),
  );
  void editEmployee([Employee? employee]) => showDialog(
    context: context,
    builder: (_) => NameEditor(
      title: employee == null ? 'Çalışan ekle' : 'Çalışanı düzenle',
      initial: employee?.name ?? '',
      role: employee?.role ?? '',
      active: employee?.active ?? true,
      onSave: (name, role, active) => store.saveEmployee(
        Employee(
          id: employee?.id ?? newId(),
          teamId: currentTeam,
          name: name,
          role: role,
          active: active,
        ),
      ),
    ),
  );
  void editTemplate([ShiftTemplate? template]) => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => ShiftEditor(
      store: store,
      date: selected,
      template: template,
      editTemplate: true,
    ),
  );
  Future<void> publish() async {
    if (await confirmAction(
      context,
      'Ekip planını yayımla',
      'Bu ekibin tüm tarihlerdeki taslağı yayımlanacak. Eklenen, düzenlenen ve silinen atamalar Demo çalışan ekranına birlikte yansıyacak.',
      'Yayımla',
    )) {
      await perform(
        () => store.publishTeam(currentTeam),
        'Ekip planı yayımlandı.',
      );
    }
  }

  void selectDay(DateTime day) => setState(() {
    selected = day;
    month = monthOf(day);
  });
  Widget heading(String title, String subtitle, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 24,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        ?action,
      ],
    ),
  );
  Widget stat(String label, String value, IconData icon, {String? hint}) =>
      SizedBox(
        width: 260,
        child: Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(hint, style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      );
  Widget stats(List<Widget> children) => LayoutBuilder(
    builder: (context, c) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: children
          .map(
            (child) => SizedBox(
              width: c.maxWidth < 580 ? c.maxWidth : (c.maxWidth - 24) / 3,
              child: child,
            ),
          )
          .toList(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    const destinations = [
      ('Kişisel', Icons.person_outline),
      ('Ekip yönetimi', Icons.grid_view_outlined),
      ('Çalışan', Icons.badge_outlined),
    ];
    final content = SafeArea(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 32 : 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                if (!wide) ...[
                  Icon(
                    Icons.view_week_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'vardiya',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 23,
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      'Çalışma alanım',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'DEMO · Yerel',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (store.busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              key: ValueKey('page-$mode-$managerTab'),
              padding: EdgeInsets.all(wide ? 32 : 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1500),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: Text(
                            'Demo modları aynı cihazdaki örnek verileri kullanır. Gerçek giriş veya yetkilendirme yoktur.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (mode == 0)
                          personalPage()
                        else if (mode == 1)
                          managerPage()
                        else
                          employeePage(),
                        const SizedBox(height: 32),
                        Text(
                          'Planlanan net çalışma süresi gösterilir. Mola, vardiya boyunca orantılı dağıtılır.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            Container(
              width: 216,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 36, 20, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.view_week_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 32,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'vardiya',
                              style: TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(26, 0, 20, 40),
                    child: Text(
                      'Zamanın bir düzeni var.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 26, vertical: 8),
                    child: Text(
                      'DEMO GÖRÜNÜMÜ',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selected: mode == i,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          leading: Icon(destinations[i].$2),
                          title: Text(
                            destinations[i].$1,
                            style: TextStyle(fontSize: 14),
                          ),
                          onTap: () => setState(() => mode = i),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Yalnız bu cihazda\nWeb · Android · iOS',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.7,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: mode,
              onDestinationSelected: (i) => setState(() => mode = i),
              destinations: destinations
                  .map(
                    (d) => NavigationDestination(icon: Icon(d.$2), label: d.$1),
                  )
                  .toList(),
            ),
    );
  }

  Widget personalPage() {
    final from = monthOf(month),
        until = DateTime.utc(month.year, month.month + 1);
    final now = DateTime.now();
    final civilNow = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final upcoming =
        data.personal
            .where((s) => s.kind == EntryKind.work && s.end.isAfter(civilNow))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Kendi ritmini planla',
          'Vardiyaların, izinlerin, sana kalan zaman.',
          action: FilledButton.icon(
            key: const Key('add-personal'),
            onPressed: () => editShift(),
            icon: Icon(Icons.add),
            label: Text('Kayıt ekle'),
          ),
        ),
        if (MediaQuery.sizeOf(context).width < 700) ...[
          calendarAndDetails(data.personal, editable: true),
          const SizedBox(height: 24),
        ],
        stats([
          stat(
            'Bu ay · Planlanan net çalışma süresi',
            durationText(netTotal(data.personal, from, until)),
            Icons.schedule,
          ),
          stat(
            'Yaklaşan / devam eden vardiya',
            upcoming.isEmpty ? 'Planın açık' : shiftTime(upcoming.first),
            Icons.event_outlined,
            hint: upcoming.isEmpty
                ? 'Yeni bir kayıt ekleyebilirsin.'
                : dateText(upcoming.first.start),
          ),
          stat(
            'Seçilen ay · İzin ve dinlenme',
            '${data.personal.where((s) => s.kind != EntryKind.work && s.intersects(from, until)).length} gün',
            Icons.weekend_outlined,
          ),
        ]),
        const SizedBox(height: 24),
        if (MediaQuery.sizeOf(context).width >= 700)
          calendarAndDetails(data.personal, editable: true),
      ],
    );
  }

  Widget calendarAndDetails(List<Shift> shifts, {required bool editable}) {
    final entries =
        shifts
            .where(
              (s) =>
                  s.intersects(selected, selected.add(const Duration(days: 1))),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final calendar = MonthCalendar(
      month: month,
      selected: selected,
      shifts: shifts,
      onSelect: selectDay,
      onMonth: (d) => setState(() {
        month = d;
        selected = d;
      }),
    );
    final detail = Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editable && MediaQuery.sizeOf(context).width < 700)
            PeriodNav(
              label: 'Günlük program',
              previous: () =>
                  selectDay(selected.subtract(const Duration(days: 1))),
              next: () => selectDay(selected.add(const Duration(days: 1))),
              today: () => selectDay(dayOf(DateTime.now())),
            ),
          Text(
            dateText(selected),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${weekNames[selected.weekday - 1]} · ${entries.length} kayıt',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            const EmptyState('Bu gün için kayıt yok.\nKendine zaman ayır.')
          else
            ...entries.map(
              (s) => ShiftTile(
                shift: s,
                day: selected,
                onEdit: editable ? () => editShift(shift: s) : null,
                onDelete: editable ? () => removeShift(s) : null,
              ),
            ),
          if (editable)
            OutlinedButton.icon(
              onPressed: () => editShift(),
              icon: Icon(Icons.add),
              label: Text('Bu güne kayıt ekle'),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 820
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: calendar),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: detail),
              ],
            )
          : Column(children: [detail, const SizedBox(height: 16), calendar]),
    );
  }

  Widget managerPage() {
    final team = data.teams.firstWhere((t) => t.id == currentTeam);
    final people = data.employees
        .where((e) => e.teamId == currentTeam)
        .toList();
    final shifts = data.draft.where((s) => s.teamId == currentTeam).toList();
    final changed = store.hasUnpublishedChanges(currentTeam);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Birlikte, planlı', 'Ekibini düzenle. Haftaya yer aç.'),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 270,
              child: DropdownButtonFormField<String>(
                key: ValueKey(currentTeam),
                initialValue: currentTeam,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ekip'),
                items: data.teams
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => teamId = v),
              ),
            ),
            IconButton(
              tooltip: 'Ekip adını düzenle',
              onPressed: () => editTeam(team),
              icon: Icon(Icons.edit_outlined),
            ),
            OutlinedButton.icon(
              onPressed: () => editTeam(),
              icon: Icon(Icons.add),
              label: Text('Yeni ekip'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            3,
            (i) => ChoiceChip(
              label: Text(['Haftalık plan', 'Çalışanlar', 'Şablonlar'][i]),
              selected: managerTab == i,
              onSelected: (_) => setState(() => managerTab = i),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (managerTab == 0) ...[
          Surface(
            child: Wrap(
              spacing: 20,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      changed
                          ? 'Taslak · Yayımlanmamış değişiklikler'
                          : 'Taslak ve yayımlanan plan aynı',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Çalışanlar yalnız son yayımlanan kopyayı görür.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: store.busy ? null : publish,
                  icon: Icon(Icons.publish_outlined),
                  label: Text('Tüm ekip taslağını yayımla'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              weekNavigation(),
              OutlinedButton.icon(
                onPressed: people.any((p) => p.active)
                    ? () => editShift(date: week)
                    : null,
                icon: Icon(Icons.add),
                label: Text('Vardiya ata'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Hafta · Planlanan net çalışma süresi: ${durationText(netTotal(shifts, week, week.add(const Duration(days: 7))))}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (people.isEmpty)
            Surface(
              child: Column(
                children: [
                  const EmptyState('Bu ekipte henüz çalışan yok.'),
                  FilledButton(
                    onPressed: () => editEmployee(),
                    child: Text('İlk çalışanı ekle'),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 800
                  ? weeklyGrid(people, shifts)
                  : mobileTeamPlan(people, shifts),
            ),
        ] else if (managerTab == 1) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => editEmployee(),
              icon: Icon(Icons.person_add_alt),
              label: Text('Çalışan ekle'),
            ),
          ),
          const SizedBox(height: 16),
          if (people.isEmpty) const EmptyState('Ekibine ilk çalışanı ekle.'),
          ...people.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                padding: const EdgeInsets.all(12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    child: Text(p.name.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.role.isEmpty ? 'Çalışan' : p.role} · ${p.active ? 'Aktif' : 'Pasif — geçmişi korunuyor'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Çalışanı düzenle',
                    icon: Icon(Icons.edit_outlined),
                    onPressed: () => editEmployee(p),
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          Text(
            'Şablonlar tüm ekiplerde kullanılabilir. Değişiklikler mevcut atamaları değiştirmez.',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => editTemplate(),
              icon: Icon(Icons.add),
              label: Text('Şablon ekle'),
            ),
          ),
          const SizedBox(height: 16),
          ...data.templates.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                padding: const EdgeInsets.all(12),
                child: ListTile(
                  title: Text(t.name),
                  subtitle: Text(
                    '${minuteText(t.startMinute)} – ${minuteText(t.endMinute)}${t.nextDay ? ' (+1 gün)' : ''}\nMola ${t.breakMinutes} dk',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Şablonu düzenle',
                    onPressed: () => editTemplate(t),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget weekNavigation() => PeriodNav(
    label:
        '${week.day} ${monthNames[week.month - 1]} – ${dateText(week.add(const Duration(days: 6)))}',
    previous: () =>
        setState(() => week = week.subtract(const Duration(days: 7))),
    next: () => setState(() => week = week.add(const Duration(days: 7))),
    today: () => setState(() {
      week = weekOf(DateTime.now());
      selected = dayOf(DateTime.now());
    }),
  );

  Widget weeklyGrid(List<Employee> people, List<Shift> shifts) => Surface(
    padding: EdgeInsets.zero,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(142),
        columnWidths: const {0: FixedColumnWidth(200)},
        border: TableBorder.symmetric(
          inside: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
            ),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'ÇALIŞAN / NET SÜRE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              ...List.generate(7, (i) {
                final d = week.add(Duration(days: i));
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${weekNames[i]}  ${d.day}',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              }),
            ],
          ),
          ...people.map(
            (p) => TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        p.active ? p.role : 'Pasif',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        durationText(
                          netTotal(
                            shifts.where((s) => s.employeeId == p.id),
                            week,
                            week.add(const Duration(days: 7)),
                          ),
                        ),
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                ...List.generate(7, (i) {
                  final d = week.add(Duration(days: i));
                  final entries =
                      shifts
                          .where(
                            (s) =>
                                s.employeeId == p.id &&
                                s.intersects(d, d.add(const Duration(days: 1))),
                          )
                          .toList()
                        ..sort((a, b) => a.start.compareTo(b.start));
                  return Padding(
                    padding: const EdgeInsets.all(7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (entries.isEmpty && !p.active)
                          Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('—'),
                          ),
                        ...entries.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: shiftColor(
                                context,
                                s,
                              ).withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => editShift(shift: s),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            shiftIcon(s),
                                            size: 14,
                                            color: shiftColor(context, s),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              s.label,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: shiftColor(context, s),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        dayOf(s.start).isBefore(d)
                                            ? 'Devam → ${clockText(s.end)}'
                                            : shiftTime(s),
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      if (!dayOf(s.start).isBefore(d))
                                        Text(
                                          'Mola ${s.breakMinutes} dk',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (p.active)
                          IconButton(
                            tooltip: '${p.name}, ${dateText(d)} vardiya ekle',
                            onPressed: () => editShift(person: p.id, date: d),
                            icon: Icon(Icons.add, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget mobileTeamPlan(List<Employee> people, List<Shift> shifts) {
    final day =
        selected.isBefore(week) ||
            !selected.isBefore(week.add(const Duration(days: 7)))
        ? week
        : selected;
    final entries =
        shifts
            .where((s) => s.intersects(day, day.add(const Duration(days: 1))))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(7, (i) {
              final d = week.add(Duration(days: i));
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${weekNames[i]} ${d.day}'),
                  selected: d == day,
                  onSelected: (_) => selectDay(d),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        Text(dateText(day), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const Surface(child: EmptyState('Bu güne henüz vardiya atanmadı.')),
        ...entries.map(
          (s) => ShiftTile(
            shift: s,
            day: day,
            employeeName: people.firstWhere((p) => p.id == s.employeeId).name,
            onEdit: () => editShift(shift: s),
            onDelete: () => removeShift(s),
          ),
        ),
      ],
    );
  }

  Widget employeePage() {
    final id = currentEmployee;
    final shifts = id == null ? <Shift>[] : data.forEmployee(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Programın burada', 'Yalnız sana yayımlanan vardiyalar.'),
        if (data.employees.isEmpty)
          const Surface(
            child: EmptyState('Yönetici görünümünden örnek çalışan ekleyin.'),
          )
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey('employee-$id'),
            initialValue: id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Demo çalışan seçimi'),
            items: data.employees
                .map(
                  (e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(
                      '${e.name}${e.active ? '' : ' (pasif)'} · ${data.teams.firstWhere((t) => t.id == e.teamId).name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => employeeId = v),
          ),
          const SizedBox(height: 12),
          Text(
            'Yayımlanmış program · Bu seçim bir giriş işlemi değildir.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          weekNavigation(),
          const SizedBox(height: 12),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bu hafta · Planlanan net çalışma süresi',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  durationText(
                    netTotal(shifts, week, week.add(const Duration(days: 7))),
                  ),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(7, (i) {
            final day = week.add(Duration(days: i));
            final entries = shifts
                .where(
                  (s) => s.intersects(day, day.add(const Duration(days: 1))),
                )
                .toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${weekNames[i]} · ${dateText(day)}',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      Text(
                        'Yayımlanmış vardiya yok',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      )
                    else
                      ...entries.map((s) => ShiftTile(shift: s, day: day)),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Text('Aylık takvim', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          calendarAndDetails(shifts, editable: false),
        ],
      ],
    );
  }
}
