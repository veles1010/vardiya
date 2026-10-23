import 'package:flutter/material.dart';

import '../domain.dart';
import '../widgets.dart';
import 'account_service.dart';
import 'plan_model.dart';

String fullPlanTime(DateTime d) => '${dateText(d)} ${clockText(d)}';
DateTime istanbulToday() =>
    dayOf(DateTime.now().toUtc().add(const Duration(hours: 3)));

class TeamPlanPage extends StatefulWidget {
  const TeamPlanPage({super.key, required this.controller});
  final AccountController controller;
  @override
  State<TeamPlanPage> createState() => _TeamPlanPageState();
}

class _TeamPlanPageState extends State<TeamPlanPage> {
  late DateTime week = weekOf(istanbulToday());
  DateTime? selectedDay;
  bool entering = true;
  AccountController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    // Every entrance fetches a fresh server snapshot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.loadPlan(draft: c.selectedTeam?.canManage ?? false);
      setState(() => entering = false);
    });
  }

  Future<void> edit([Shift? shift]) async {
    final epochUser = c.user?.id, team = c.selectedTeam?.id;
    final snapshot = c.plan;
    if (snapshot == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CloudShiftEditor(
        controller: c,
        shift: shift,
        day: selectedDay ?? week,
        version: snapshot.version,
        userId: epochUser!,
        teamId: team!,
      ),
    );
  }

  Future<void> remove(Shift shift) async {
    final version = c.plan?.version, user = c.user?.id;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Taslak vardiyayı sil'),
        content: const Text(
          'Yayımlanmış program yeniden yayımlanana kadar korunur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (yes == true && user == c.user?.id && version == c.plan?.version) {
      await c.deletePlanShift(shift.id);
    }
  }

  Future<void> publish() async {
    final version = c.plan?.version, user = c.user?.id;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tüm ekip taslağını yayımla'),
        content: const Text(
          'Bu işlem yalnız seçili haftayı değil, tüm tarihlerdeki ekip taslağını yayımlar. Tüm üyelerin önceki yayımlanmış programı bu kopyayla değiştirilir. Taslaktan silinen vardiyalar da kaldırılır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tüm tarihleri yayımla'),
          ),
        ],
      ),
    );
    if (yes == true && user == c.user?.id && version == c.plan?.version) {
      await c.publishPlan();
    }
  }

  Widget tile(Shift s, {DateTime? day, bool closeFirst = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${fullPlanTime(s.start)} → ${fullPlanTime(s.end)}'),
      ShiftTile(
        shift: s,
        day: day,
        employeeName: memberName(s.employeeId),
        onEdit: editable
            ? () {
                if (closeFirst) Navigator.pop(context);
                edit(s);
              }
            : null,
        onDelete: editable
            ? () {
                if (closeFirst) Navigator.pop(context);
                remove(s);
              }
            : null,
      ),
    ],
  );
  bool get editable =>
      c.selectedTeam?.canManage == true &&
      c.planDraft &&
      !c.busy &&
      !c.loadingPlan &&
      !c.planStale;
  String memberName(String? id) =>
      c.teamMembers.where((m) => m.id == id).firstOrNull?.email ?? 'Ekip üyesi';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final team = c.selectedTeam;
      if (team == null || c.user == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Ekip planı')),
          body: const Center(
            child: Text(
              'Oturum veya ekip değişti. Hesap bölümünden ekibi yeniden açın.',
            ),
          ),
        );
      }
      final plan = entering ? null : c.plan;
      final until = week.add(const Duration(days: 7));
      final shifts =
          plan?.shifts.where((s) => s.intersects(week, until)).toList() ??
          <Shift>[];
      final displayed = selectedDay == null
          ? shifts
          : shifts
                .where(
                  (s) => s.intersects(
                    selectedDay!,
                    selectedDay!.add(const Duration(days: 1)),
                  ),
                )
                .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            '${team.name} · Haftalık plan',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 28),
            children: [
              const Text(
                'Gerçek ekip · Europe/Istanbul (Türkiye saati)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                team.canManage
                    ? 'Taslak yalnız yöneticilere açıktır. Çalışanlar son yayımlanmış kopyayı görür.'
                    : 'Yalnız size ait yayımlanmış program gösterilir.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (team.canManage) ...[
                    ChoiceChip(
                      label: const Text('Taslak'),
                      selected: c.planDraft,
                      onSelected: c.busy || c.loadingPlan
                          ? null
                          : (_) => c.loadPlan(draft: true),
                    ),
                    ChoiceChip(
                      label: const Text('Yayımlanmış'),
                      selected: !c.planDraft,
                      onSelected: c.busy || c.loadingPlan
                          ? null
                          : (_) => c.loadPlan(draft: false),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: c.busy || c.loadingPlan
                        ? null
                        : () => c.loadPlan(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Yenile'),
                  ),
                  if (team.canManage && c.planDraft) ...[
                    FilledButton.icon(
                      onPressed: editable && plan != null ? () => edit() : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Vardiya ata'),
                    ),
                    OutlinedButton.icon(
                      onPressed: editable && plan != null ? publish : null,
                      icon: const Icon(Icons.publish),
                      label: const Text('Yayımla · Tüm ekip taslağı'),
                    ),
                  ],
                ],
              ),
              if (entering || c.loadingPlan) const LinearProgressIndicator(),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (c.planStale)
                const Text(
                  'Yeni işlemden önce Yenile ile sunucudaki güncel planı alın.',
                ),
              if (plan != null)
                Text(
                  'Sürüm ${plan.version} · ${plan.publishedVersion == null ? 'Henüz yayımlanmadı' : 'Son yayımlanan sürüm ${plan.publishedVersion}'}',
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Önceki hafta',
                    onPressed: () => setState(() {
                      week = week.subtract(const Duration(days: 7));
                      selectedDay = null;
                    }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${dateText(week)} – ${dateText(until.subtract(const Duration(days: 1)))}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: 'Sonraki hafta',
                    onPressed: () => setState(() {
                      week = until;
                      selectedDay = null;
                    }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      week = weekOf(istanbulToday());
                      selectedDay = null;
                    }),
                    child: const Text('Bu hafta'),
                  ),
                ],
              ),
              if (plan != null) ...[
                Text(
                  'Haftanın planlanan net çalışma süresi${team.canManage ? ' (ekip)' : ''}: ${durationText(shifts.fold(0.0, (v, s) => v + s.netInPeriod(week, until)))}',
                ),
                const SizedBox(height: 12),
                if (!c.planDraft && plan.publishedVersion == null)
                  const EmptyState('Bu ekip için henüz program yayımlanmadı.')
                else if (constraints.maxWidth >= 900 && team.canManage)
                  grid(shifts)
                else ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Tüm hafta'),
                        selected: selectedDay == null,
                        onSelected: (_) => setState(() => selectedDay = null),
                      ),
                      for (var i = 0; i < 7; i++)
                        ChoiceChip(
                          label: Text(
                            '${weekNames[i]} ${week.add(Duration(days: i)).day}',
                          ),
                          selected: selectedDay == week.add(Duration(days: i)),
                          onSelected: (_) => setState(
                            () => selectedDay = week.add(Duration(days: i)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (displayed.isEmpty)
                    const EmptyState('Bu dönemde vardiya yok.'),
                  ...displayed.map((s) => tile(s, day: selectedDay)),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget grid(List<Shift> shifts) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      defaultColumnWidth: const FixedColumnWidth(155),
      columnWidths: const {0: FixedColumnWidth(190)},
      children: [
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text('Ekip üyesi'),
            ),
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  '${weekNames[i]} ${dateText(week.add(Duration(days: i)))}',
                ),
              ),
          ],
        ),
        for (final member in c.teamMembers)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(member.email),
              ),
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      for (final s in shifts.where(
                        (s) =>
                            s.employeeId == member.id &&
                            s.intersects(
                              week.add(Duration(days: i)),
                              week.add(Duration(days: i + 1)),
                            ),
                      ))
                        Card(
                          child: InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => AnimatedBuilder(
                                animation: c,
                                builder: (context, _) {
                                  final current = c.plan?.shifts
                                      .where((x) => x.id == s.id)
                                      .firstOrNull;
                                  if (current == null) {
                                    return const AlertDialog(
                                      content: Text(
                                        'Plan veya oturum değişti. Ayrıntıyı kapatıp yenileyin.',
                                      ),
                                    );
                                  }
                                  return AlertDialog(
                                    title: Text(current.label),
                                    content: SingleChildScrollView(
                                      child: tile(
                                        current,
                                        day: week.add(Duration(days: i)),
                                        closeFirst: true,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Kapat'),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Text(
                                    s.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${clockText(s.start)}–${clockText(s.end)}',
                                  ),
                                  if (dayOf(s.end) != dayOf(s.start))
                                    const Text('Gece / gün aşımı'),
                                  Text(
                                    durationText(
                                      s.netInPeriod(
                                        week.add(Duration(days: i)),
                                        week.add(Duration(days: i + 1)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

class CloudShiftEditor extends StatefulWidget {
  const CloudShiftEditor({
    super.key,
    required this.controller,
    required this.day,
    required this.version,
    required this.userId,
    required this.teamId,
    this.shift,
  });
  final AccountController controller;
  final DateTime day;
  final int version;
  final String userId, teamId;
  final Shift? shift;
  @override
  State<CloudShiftEditor> createState() => _CloudShiftEditorState();
}

class _CloudShiftEditorState extends State<CloudShiftEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, start, end, pause, note;
  String? member, error;
  bool saving = false;
  String input(DateTime d) =>
      planTime(d).substring(0, 16).replaceFirst('T', ' ');
  @override
  void initState() {
    super.initState();
    final s = widget.shift;
    member = s?.employeeId ?? widget.controller.teamMembers.firstOrNull?.id;
    name = TextEditingController(text: s?.label ?? 'Vardiya');
    start = TextEditingController(
      text: input(s?.start ?? widget.day.add(const Duration(hours: 8))),
    );
    end = TextEditingController(
      text: input(s?.end ?? widget.day.add(const Duration(hours: 16))),
    );
    pause = TextEditingController(text: '${s?.breakMinutes ?? 30}');
    note = TextEditingController(text: s?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [name, start, end, pause, note]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime parse(String text) {
    if (!RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d$').hasMatch(text)) {
      throw const RuleViolation(
        'Tarih ve saati YYYY-AA-GG SS:dd biçiminde girin.',
      );
    }
    final d = DateTime.tryParse('${text.replaceFirst(' ', 'T')}Z');
    if (d == null || input(d) != text) {
      throw const RuleViolation(
        'Geçerli bir tarih ve 24 saat biçiminde saat girin.',
      );
    }
    return d;
  }

  Shift candidate() {
    final b = int.tryParse(pause.text);
    if (b == null || member == null) {
      throw const RuleViolation('Ekip üyesini ve dakika olarak molayı seçin.');
    }
    final s = Shift(
      id: widget.shift?.id ?? '',
      teamId: widget.teamId,
      employeeId: member,
      start: parse(start.text.trim()),
      end: parse(end.text.trim()),
      breakMinutes: b,
      label: name.text.trim(),
      note: note.text.trim(),
    );
    s.validate();
    return s;
  }

  Future<void> save() async {
    final c = widget.controller;
    if (c.user?.id != widget.userId ||
        c.selectedTeam?.id != widget.teamId ||
        c.plan?.version != widget.version) {
      setState(
        () =>
            error = 'Oturum veya plan değişti. Formu kapatıp planı yenileyin.',
      );
      return;
    }
    if (!form.currentState!.validate()) return;
    try {
      final s = candidate();
      checkConflicts(s, c.plan!.shifts);
      setState(() => saving = true);
      final ok = await c.savePlanShift(s, creating: widget.shift == null);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
      } else {
        setState(() {
          saving = false;
          error = c.error ?? 'Planı yenileyip yeniden deneyin.';
        });
      }
    } on RuleViolation catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.user?.id != widget.userId ||
          widget.controller.selectedTeam?.id != widget.teamId) {
        return AlertDialog(
          content: const Text('Oturum veya ekip değişti. Formu kapatın.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        );
      }
      String preview;
      try {
        final s = candidate();
        preview =
            'Bitiş: ${fullPlanTime(s.end)}\nPlanlanan net çalışma süresi: ${durationText(s.netMinutes)}';
      } on RuleViolation catch (e) {
        preview = e.message;
      }
      return AlertDialog(
        title: Text(
          widget.shift == null
              ? 'Taslak vardiya ata'
              : 'Taslak vardiyayı düzenle',
        ),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Form(
            key: form,
            onChanged: () => setState(() => error = null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Europe/Istanbul · Türkiye saati. Gece vardiyasında bitiş tarihini ertesi gün olarak girin.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: member,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ekip üyesi'),
                  items: widget.controller.teamMembers
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.email, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: saving ? null : (v) => setState(() => member = v),
                ),
                field(name, 'Vardiya adı', max: 100),
                field(start, 'Başlangıç · YYYY-AA-GG SS:dd'),
                field(end, 'Bitiş · YYYY-AA-GG SS:dd'),
                field(pause, 'Ücretsiz mola (dakika)', number: true),
                field(note, 'Not (isteğe bağlı)', max: 2000, optional: true),
                Text(
                  preview,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      );
    },
  );
  Widget field(
    TextEditingController c,
    String label, {
    bool number = false,
    int? max,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c,
      enabled: !saving,
      maxLength: max,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (v) => !optional && (v?.trim().isEmpty ?? true)
          ? 'Bu alanı doldurun.'
          : null,
    ),
  );
}
