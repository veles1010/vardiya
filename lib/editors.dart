import 'package:flutter/material.dart';

import 'data.dart';
import 'domain.dart';
import 'widgets.dart';

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class NameEditor extends StatefulWidget {
  const NameEditor({
    super.key,
    required this.title,
    required this.initial,
    required this.onSave,
    this.role,
    this.active = true,
  });
  final String title, initial;
  final String? role;
  final bool active;
  final Future<void> Function(String name, String role, bool active) onSave;
  @override
  State<NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<NameEditor> {
  late final name = TextEditingController(text: widget.initial);
  late final role = TextEditingController(text: widget.role);
  late bool active = widget.active;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    role.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Ad boş bırakılamaz.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(name.text.trim(), role.text.trim(), active);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e, stack) {
      if (e is! RuleViolation) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: stack, library: 'Vardiya'),
        );
      }
      if (mounted) {
        setState(() {
          error = errorText(e);
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ad'),
          ),
          if (widget.role != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: role,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Görev / unvan (isteğe bağlı)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktif çalışan'),
              subtitle: const Text('Pasifleştirmek geçmiş atamaları silmez.'),
              value: active,
              onChanged: saving ? null : (v) => setState(() => active = v),
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Kaydediliyor…' : 'Kaydet'),
      ),
    ],
  );
}

class ShiftEditor extends StatefulWidget {
  const ShiftEditor({
    super.key,
    required this.store,
    required this.date,
    this.shift,
    this.personal = true,
    this.teamId,
    this.employeeId,
    this.template,
    this.editTemplate = false,
  });
  final ScheduleStore store;
  final DateTime date;
  final Shift? shift;
  final bool personal, editTemplate;
  final String? teamId, employeeId;
  final ShiftTemplate? template;
  @override
  State<ShiftEditor> createState() => _ShiftEditorState();
}

class _ShiftEditorState extends State<ShiftEditor> {
  final form = GlobalKey<FormState>();
  late final label = TextEditingController(
    text: widget.template?.name ?? widget.shift?.label ?? 'Vardiya',
  );
  late final note = TextEditingController(text: widget.shift?.note ?? '');
  late final start = TextEditingController(
    text: widget.template != null
        ? minuteText(widget.template!.startMinute)
        : widget.shift != null
        ? clockText(widget.shift!.start)
        : '08:00',
  );
  late final end = TextEditingController(
    text: widget.template != null
        ? minuteText(widget.template!.endMinute)
        : widget.shift != null
        ? clockText(widget.shift!.end)
        : '16:00',
  );
  late final rest = TextEditingController(
    text:
        '${widget.template?.breakMinutes ?? widget.shift?.breakMinutes ?? 30}',
  );
  late DateTime date = dayOf(widget.shift?.start ?? widget.date);
  late EntryKind kind = widget.shift?.kind ?? EntryKind.work;
  late bool nextDay =
      widget.template?.nextDay ??
      (widget.shift != null &&
          dayOf(widget.shift!.end) != dayOf(widget.shift!.start));
  late String? employeeId = widget.shift?.employeeId ?? widget.employeeId;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final controller in [label, note, start, end, rest]) {
      controller.addListener(valuesChanged);
    }
  }

  void valuesChanged() {
    if (mounted) {
      setState(() => error = null);
    }
  }

  Widget calculationPreview() {
    final first = parseTime(start.text);
    final last = parseTime(end.text);
    final pause = int.tryParse(rest.text);
    String text;
    try {
      if (first == null || last == null || pause == null) {
        text = 'Bitiş ve net süre için geçerli saat ve mola girin.';
      } else {
        final result = timedShift(
          id: 'preview',
          date: date,
          startMinute: first,
          endMinute: last,
          nextDay: nextDay,
          breakMinutes: pause,
        );
        text =
            'Hesaplanan bitiş: ${dateText(result.end)} ${clockText(result.end)}\nPlanlanan net çalışma süresi: ${durationText(result.netMinutes)}';
      }
    } on RuleViolation catch (e) {
      text = e.message;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        key: const Key('calculation-preview'),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }

  int? parseTime(String text) {
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(text.trim());
    if (m == null) {
      return null;
    }
    final h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    return h <= 23 && min <= 59 ? h * 60 + min : null;
  }

  @override
  void dispose() {
    for (final c in [label, note, start, end, rest]) {
      c.removeListener(valuesChanged);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.editTemplate) {
        await widget.store.saveTemplate(
          ShiftTemplate(
            id: widget.template?.id ?? newId(),
            name: label.text.trim(),
            startMinute: parseTime(start.text)!,
            endMinute: parseTime(end.text)!,
            breakMinutes: int.parse(rest.text),
            nextDay: nextDay,
          ),
        );
      } else {
        final shift = kind == EntryKind.work
            ? timedShift(
                id: widget.shift?.id ?? newId(),
                date: date,
                startMinute: parseTime(start.text)!,
                endMinute: parseTime(end.text)!,
                nextDay: nextDay,
                breakMinutes: int.parse(rest.text),
                label: label.text.trim(),
                note: note.text.trim(),
                employeeId: widget.personal ? null : employeeId,
                teamId: widget.personal ? null : widget.teamId,
              )
            : Shift(
                id: widget.shift?.id ?? newId(),
                start: date,
                end: date.add(const Duration(days: 1)),
                label: label.text.trim(),
                kind: kind,
                note: note.text.trim(),
              );
        await widget.store.saveShift(shift, personal: widget.personal);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e, stack) {
      if (e is! RuleViolation) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: stack, library: 'Vardiya'),
        );
      }
      if (mounted) {
        setState(() {
          error = errorText(e);
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.store.data.employees
        .where(
          (e) =>
              e.teamId == widget.teamId &&
              (e.active || e.id == widget.shift?.employeeId),
        )
        .toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: Text(
        widget.editTemplate
            ? 'Vardiya şablonu'
            : widget.shift == null
            ? (widget.personal ? 'Kişisel kayıt ekle' : 'Taslağa vardiya ata')
            : 'Kaydı düzenle',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: valuesChanged,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.personal && !widget.editTemplate) ...[
                DropdownButtonFormField<String>(
                  initialValue: employeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Çalışan'),
                  items: people
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            '${e.name}${e.active ? '' : ' (pasif)'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (v) => v == null ? 'Çalışan seçin.' : null,
                  onChanged: saving
                      ? null
                      : (v) => setState(() {
                          employeeId = v;
                          error = null;
                        }),
                ),
                const SizedBox(height: 16),
              ],
              if (widget.personal && !widget.editTemplate) ...[
                DropdownButtonFormField<EntryKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Kayıt türü'),
                  items: EntryKind.values
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(kindText(k)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    error = null;
                    kind = v!;
                    label.text = kindText(kind);
                  }),
                ),
                const SizedBox(height: 16),
              ],
              if (!widget.editTemplate) ...[
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final result = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (result != null) {
                            setState(() {
                              date = dayOf(result);
                              error = null;
                            });
                          }
                        },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(dateText(date)),
                ),
                const SizedBox(height: 12),
              ],
              if (kind == EntryKind.work && !widget.editTemplate) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Şablondan doldur (isteğe bağlı)',
                  ),
                  items: widget.store.data.templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            '${t.name} · ${minuteText(t.startMinute)}–${minuteText(t.endMinute)}${t.nextDay ? ' (+1 gün)' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    final t = widget.store.data.templates.firstWhere(
                      (t) => t.id == id,
                    );
                    setState(() {
                      error = null;
                      label.text = t.name;
                      start.text = minuteText(t.startMinute);
                      end.text = minuteText(t.endMinute);
                      rest.text = '${t.breakMinutes}';
                      nextDay = t.nextDay;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: label,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Kayıt adı'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Kayıt adı gerekli.' : null,
              ),
              if (kind == EntryKind.work) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: start,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Başlangıç',
                          hintText: '08:00',
                        ),
                        validator: (v) =>
                            parseTime(v ?? '') == null ? 'SS:DD girin.' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: end,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Bitiş',
                          hintText: '16:00',
                        ),
                        validator: (v) =>
                            parseTime(v ?? '') == null ? 'SS:DD girin.' : null,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ertesi gün biter'),
                  subtitle: Text(
                    nextDay
                        ? 'Bitiş: ${dateText(date.add(const Duration(days: 1)))}'
                        : 'Başlangıç ve bitiş aynı gün',
                  ),
                  value: nextDay,
                  onChanged: (v) => setState(() {
                    nextDay = v;
                    error = null;
                  }),
                ),
                TextFormField(
                  controller: rest,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Ücretsiz mola (dakika)',
                  ),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ? 'Tam sayı girin.' : null,
                ),
              ],
              if (kind == EntryKind.work) calculationPreview(),
              if (!widget.editTemplate) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: note,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Not (isteğe bağlı)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        error!,
                        key: const Key('form-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.shift != null)
          TextButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final yes = await confirmAction(
                      context,
                      'Kaydı sil',
                      widget.personal ? 'Kişisel kayıt silinsin mi?' : 'Kayıt taslaktan silinsin mi? Çalışan görünümü yeniden yayımlanana kadar değişmez.',
                      'Sil',
                    );
                    if (!yes || !mounted) {
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      await widget.store.deleteShift(
                        widget.shift!.id,
                        personal: widget.personal,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          error = errorText(e);
                        });
                      }
                    }
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Sil'),
          ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Kaydediliyor…' : 'Kaydet'),
        ),
      ],
    );
  }
}
