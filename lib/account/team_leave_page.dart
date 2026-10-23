import 'package:flutter/material.dart';

import '../domain.dart';
import '../widgets.dart';
import 'account_service.dart';
import 'leave_model.dart';

DateTime _today() =>
    dayOf(DateTime.now().toUtc().add(const Duration(hours: 3)));
String _stamp(DateTime value) {
  final d = value.toUtc().add(const Duration(hours: 3));
  return '${dateText(d)} ${clockText(d)}';
}

String _range(LeaveRequest r) =>
    '${dateText(r.start)} – ${dateText(r.end)} (günler dahil)';

class TeamLeavePage extends StatefulWidget {
  const TeamLeavePage({super.key, required this.controller});
  final AccountController controller;
  @override
  State<TeamLeavePage> createState() => _TeamLeavePageState();
}

class _TeamLeavePageState extends State<TeamLeavePage> {
  AccountController get c => widget.controller;
  bool entering = true;
  String? selectedStatus;
  (String?, String?)? filterScope;
  static const filters = [
    (null, 'Tümü'),
    ('pending', 'Bekliyor'),
    ('approved', 'Onaylandı'),
    ('rejected', 'Reddedildi'),
    ('cancelled', 'İptal/Geri çekildi'),
  ];

  void resetFilterOnScopeChange() {
    final scope = (c.user?.id, c.selectedTeam?.id);
    if (filterScope == scope) return;
    setState(() {
      filterScope = scope;
      selectedStatus = null;
    });
  }

  @override
  void initState() {
    super.initState();
    filterScope = (c.user?.id, c.selectedTeam?.id);
    c.addListener(resetFilterOnScopeChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.loadLeaves();
      setState(() => entering = false);
    });
  }

  @override
  void didUpdateWidget(covariant TeamLeavePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(resetFilterOnScopeChange);
      c.addListener(resetFilterOnScopeChange);
      resetFilterOnScopeChange();
    }
  }

  @override
  void dispose() {
    c.removeListener(resetFilterOnScopeChange);
    super.dispose();
  }

  String name(String id) =>
      c.teamMembers.where((m) => m.id == id).firstOrNull?.email ?? 'Üye ($id)';
  bool get enabled =>
      !c.busy && !c.loadingLeaves && !c.leavesStale && c.leaveInbox != null;
  Future<void> create() async {
    final user = c.user?.id,
        team = c.selectedTeam?.id,
        version = c.leaveInbox?.version;
    if (user == null || team == null || version == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LeaveRequestDialog(
        controller: c,
        userId: user,
        teamId: team,
        version: version,
      ),
    );
  }

  Future<void> decide(LeaveRequest r, String action) async {
    final requiredReason = action == 'reject' || action == 'cancel';
    final title = switch (action) {
      'approve' => 'İzni onayla',
      'reject' => 'Talebi reddet',
      'cancel' => 'Onaylı izni iptal et',
      _ => 'Talebi geri çek',
    };
    final user = c.user?.id,
        team = c.selectedTeam?.id,
        version = c.leaveInbox?.version;
    if (user == null || team == null || version == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _LeaveDecisionDialog(
        controller: c,
        userId: user,
        teamId: team,
        title: title,
        request: r,
        requiredReason: requiredReason,
        approve: action == 'approve',
      ),
    );
    if (reason == null || user != c.user?.id || team != c.selectedTeam?.id) {
      return;
    }
    if (version != c.leaveInbox?.version) {
      c.error = 'Plan veya talep değişti. Yenile ile güncel veriyi alın ve kararı yeniden verin.';
      c.leavesStale = true;
      c.emit();
      return;
    }
    final ok = await c.actOnLeave(r, action, reason);
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Talep güncellendi.')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final team = c.selectedTeam;
      final requests = c.leaveInbox?.requests ?? const <LeaveRequest>[];
      final counts = <String?, int>{null: requests.length};
      for (final request in requests) {
        counts.update(request.status, (count) => count + 1, ifAbsent: () => 1);
      }
      final visible = requests
          .where((r) => selectedStatus == null || r.status == selectedStatus)
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            '${team?.name ?? 'Ekip'} · İzin talepleri',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: team == null || c.user == null
            ? const Center(
                child: Text('Oturum veya ekip değişti. Ekibi yeniden açın.'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Gerçek ekip · Tam gün · Europe/Istanbul',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    team.canManage
                        ? 'Yalnız bu ekibin talepleri gösterilir. Onaylı izin iptali ve ret için gerekçe gerekir.'
                        : 'Yalnız kendi talepleriniz gösterilir. Bekleyen talepler izin onayı değildir.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: c.busy || c.loadingLeaves
                            ? null
                            : c.loadLeaves,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Yenile'),
                      ),
                      if (team.role == 'employee')
                        FilledButton.icon(
                          onPressed: enabled ? create : null,
                          icon: const Icon(Icons.beach_access_outlined),
                          label: const Text('İzin talep et'),
                        ),
                    ],
                  ),
                  if (entering || c.loadingLeaves)
                    const LinearProgressIndicator(),
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
                  if (c.leavesStale)
                    const Text(
                      'İşlemden önce Yenile ile güncel plan ve talepleri alın.',
                    ),
                  if (!entering && c.leaveInbox != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (status, label) in filters)
                          ChoiceChip(
                            key: ValueKey('leave-filter-${status ?? 'all'}'),
                            label: Text('$label (${counts[status] ?? 0})'),
                            selected: selectedStatus == status,
                            onSelected: (_) =>
                                setState(() => selectedStatus = status),
                          ),
                      ],
                    ),
                  ],
                  if (!entering &&
                      !c.loadingLeaves &&
                      c.leaveInbox != null &&
                      visible.isEmpty)
                    EmptyState(
                      requests.isEmpty
                          ? 'Henüz izin talebi yok.'
                          : 'Seçili duruma uygun izin talebi yok.',
                    ),
                  if (!entering) ...visible.map((r) => card(r, team.canManage)),
                ],
              ),
      );
    },
  );
  Widget card(LeaveRequest r, bool manager) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (r.status) {
      'approved' => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      'pending' => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.hourglass_empty,
      ),
      'rejected' => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.block,
      ),
      _ => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        Icons.cancel_outlined,
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (manager)
              Text(
                name(r.userId),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            Text(
              _range(r),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                backgroundColor: bg,
                avatar: Icon(icon, color: fg, size: 18),
                label: Text(leaveStatus(r.status), style: TextStyle(color: fg)),
              ),
            ),
            Text(r.description.isEmpty ? 'Açıklama yok.' : r.description),
            if (manager && r.conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Onayı engelleyen vardiyalar',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Vardiyaları düzenleyip yeniden yayımlayın, ardından talepleri yenileyin. Otomatik silme yapılmaz.',
              ),
              for (final s in r.conflicts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${s.source == 'draft' ? 'Taslak' : 'Yayımlanmış'} · ${s.label}\n${dateText(s.start)} ${clockText(s.start)} → ${dateText(s.end)} ${clockText(s.end)}',
                  ),
                ),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (r.status == 'pending' && r.userId == c.user?.id)
                  TextButton(
                    onPressed: enabled ? () => decide(r, 'withdraw') : null,
                    child: const Text('Talebi geri çek'),
                  ),
                if (manager &&
                    r.userId != c.user?.id &&
                    r.status == 'pending') ...[
                  FilledButton(
                    onPressed: enabled && r.conflicts.isEmpty
                        ? () => decide(r, 'approve')
                        : null,
                    child: const Text('Onayla'),
                  ),
                  OutlinedButton(
                    onPressed: enabled ? () => decide(r, 'reject') : null,
                    child: const Text('Reddet'),
                  ),
                ],
                if (manager && r.userId != c.user?.id && r.status == 'approved')
                  OutlinedButton(
                    onPressed: enabled ? () => decide(r, 'cancel') : null,
                    child: const Text('Onaylı izni iptal et'),
                  ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('İşlem geçmişi'),
              children: [
                for (final e in r.events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${leaveStatus(e.status)} · ${name(e.actor)}'),
                    subtitle: Text(
                      '${_stamp(e.at)} · Türkiye saati${e.reason.isEmpty ? '' : '\nGerekçe: ${e.reason}'}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveDecisionDialog extends StatefulWidget {
  const _LeaveDecisionDialog({
    required this.controller,
    required this.userId,
    required this.teamId,
    required this.title,
    required this.request,
    required this.requiredReason,
    required this.approve,
  });
  final AccountController controller;
  final String userId, teamId, title;
  final LeaveRequest request;
  final bool requiredReason, approve;
  @override
  State<_LeaveDecisionDialog> createState() => _LeaveDecisionDialogState();
}

class _LeaveDecisionDialogState extends State<_LeaveDecisionDialog> {
  final text = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final valid =
          widget.controller.user?.id == widget.userId &&
          widget.controller.selectedTeam?.id == widget.teamId;
      return AlertDialog(
        title: Text(widget.title),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: valid
              ? Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_range(widget.request)),
                      const SizedBox(height: 12),
                      Text(
                        widget.approve
                            ? 'İzin, taslak ve yayımlanmış vardiyalarla sunucuda tekrar kontrol edilir. Onaylı günler çalışma süresine eklenmez.'
                            : 'İşlem geçmişte saklanır; talep silinmez.',
                      ),
                      if (widget.requiredReason)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextFormField(
                            controller: text,
                            autofocus: true,
                            maxLength: 500,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Gerekçe',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Gerekçe girin.'
                                : null,
                          ),
                        ),
                    ],
                  ),
                )
              : const Text('Oturum veya ekip değişti. Ekranı kapatın.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          if (valid)
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, text.text.trim());
                }
              },
              child: Text(widget.title),
            ),
        ],
      );
    },
  );
}

class LeaveRequestDialog extends StatefulWidget {
  const LeaveRequestDialog({
    super.key,
    required this.controller,
    required this.userId,
    required this.teamId,
    required this.version,
  });
  final AccountController controller;
  final String userId, teamId;
  final int version;
  @override
  State<LeaveRequestDialog> createState() => _LeaveRequestDialogState();
}

class _LeaveRequestDialogState extends State<LeaveRequestDialog> {
  DateTime first = _today(), last = _today();
  final description = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> pick(bool start) async {
    final result = await showDatePicker(
      context: context,
      initialDate: start ? first : last,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: start ? 'Başlangıç gününü seçin' : 'Bitiş gününü seçin',
    );
    if (result != null && mounted) {
      setState(() {
        if (start) {
          first = dayOf(result);
          if (last.isBefore(first)) last = first;
        } else {
          last = dayOf(result);
        }
        error = null;
      });
    }
  }

  Future<void> save() async {
    final c = widget.controller;
    if (c.user?.id != widget.userId ||
        c.selectedTeam?.id != widget.teamId ||
        c.leaveInbox?.version != widget.version) {
      setState(
        () => error = 'Oturum veya plan değişti. Formu kapatıp Yenile seçin.',
      );
      return;
    }
    if (last.isBefore(first)) {
      setState(() => error = 'Bitiş günü başlangıç gününden önce olamaz.');
      return;
    }
    setState(() => saving = true);
    final ok = await c.createLeave(first, last, description.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error =
            '${c.error ?? 'Talep gönderilemedi.'}\nFormu kapatıp Yenile ile güncel talepleri alın.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final valid =
          widget.controller.user?.id == widget.userId &&
          widget.controller.selectedTeam?.id == widget.teamId;
      return AlertDialog(
        title: const Text('Tam gün izin talebi'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: valid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Başlangıç ve bitiş günleri dahildir. Talep, yönetici onayına kadar Bekliyor durumundadır.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () => pick(true),
                      icon: const Icon(Icons.date_range),
                      label: Text('Başlangıç günü · ${dateText(first)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () => pick(false),
                      icon: const Icon(Icons.date_range),
                      label: Text('Bitiş günü · ${dateText(last)}'),
                    ),
                    if (!last.isBefore(first))
                      Text(
                        '${last.difference(first).inDays + 1} tam gün · Europe/Istanbul',
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      enabled: !saving,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Kısa açıklama (isteğe bağlı)',
                      ),
                      onChanged: (_) => setState(() => error = null),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                )
              : const Text('Oturum veya ekip değişti. Formu kapatın.'),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          if (valid)
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Gönderiliyor…' : 'Talebi gönder'),
            ),
        ],
      );
    },
  );
}
