import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_service.dart';
import 'team_plan_page.dart';
import 'team_leave_page.dart';

String roleLabel(String role) => switch (role) {
  'owner' => 'Sahip',
  'manager' => 'Yönetici',
  _ => 'Çalışan',
};
String expiryLabel(DateTime timestamp) {
  final d = timestamp.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class InvitationPanel extends StatefulWidget {
  const InvitationPanel({super.key, required this.controller});
  final AccountController controller;
  @override
  State<InvitationPanel> createState() => _InvitationPanelState();
}

class _InvitationPanelState extends State<InvitationPanel> {
  final code = TextEditingController(), email = TextEditingController();
  final joinForm = GlobalKey<FormState>(), inviteForm = GlobalKey<FormState>();
  AccountController get c => widget.controller;
  @override
  void dispose() {
    code.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = c.selectedTeam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text('Ekibe katıl', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Davet kodunu girin. Kabul etmeden önce ekip adını göreceksiniz.',
        ),
        const SizedBox(height: 12),
        Form(
          key: joinForm,
          child: TextFormField(
            controller: code,
            enabled: !c.busy,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Davet kodu'),
            onChanged: (_) => c.clearInvitationPreview(),
            validator: (v) =>
                v == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(v.trim())
                ? '64 karakterlik davet kodunu girin.'
                : null,
          ),
        ),
        OutlinedButton(
          onPressed: c.busy
              ? null
              : () {
                  if (joinForm.currentState!.validate()) {
                    c.previewInvitation(code.text);
                  }
                },
          child: const Text('Daveti kontrol et'),
        ),
        if (c.invitePreview case final preview?)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Katılacağınız ekip: ${preview.teamName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Rolünüz: Çalışan\nSon kabul: ${expiryLabel(preview.expiresAt)}',
                  ),
                  FilledButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            await c.acceptInvitation();
                            if (mounted &&
                                c.invitePreview == null &&
                                c.error == null) {
                              code.clear();
                            }
                          },
                    child: const Text('Daveti kabul et'),
                  ),
                ],
              ),
            ),
          ),
        if (team != null) ...[
          const SizedBox(height: 24),
          const Divider(),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(team.name, style: Theme.of(context).textTheme.titleLarge),
              Text('Rolünüz: ${roleLabel(team.role)}'),
              TextButton(
                onPressed: () {
                  c.clearTeamDetails();
                  c.emit();
                },
                child: const Text('Ayrıntıyı kapat'),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: c.loadingDetails || c.busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TeamPlanPage(controller: c),
                    ),
                  ),
            icon: const Icon(Icons.calendar_view_week),
            label: const Text('Haftalık planı aç'),
          ),
          OutlinedButton.icon(
            onPressed: c.loadingDetails || c.busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TeamLeavePage(controller: c),
                    ),
                  ),
            icon: const Icon(Icons.beach_access_outlined),
            label: const Text('İzin talepleri'),
          ),
          OutlinedButton.icon(
            onPressed: c.loadingDetails || c.busy ? null : c.loadDetails,
            icon: const Icon(Icons.refresh),
            label: const Text('Üyeleri yenile'),
          ),
          if (c.loadingDetails) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text(
            'Ekip üyeleri',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (!c.loadingDetails && c.teamMembers.isEmpty)
            const Text('Üye listesi boş veya yüklenemedi.'),
          ...c.teamMembers.map(
            (m) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.email),
              subtitle: Text(roleLabel(m.role)),
              leading: const Icon(Icons.person_outline),
            ),
          ),
          if (team.canManage) ...[
            const SizedBox(height: 20),
            const Text(
              'Çalışan davet et',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'E-posta gönderilmez. Davet yalnız bu e-posta ile doğrulanmış hesapta kullanılabilir; 7 gün geçerlidir.',
            ),
            const SizedBox(height: 12),
            Form(
              key: inviteForm,
              child: TextFormField(
                controller: email,
                enabled: !c.busy,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Çalışanın e-postası',
                ),
                validator: (v) =>
                    v == null ||
                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(v.trim())
                    ? 'Geçerli bir e-posta girin.'
                    : null,
              ),
            ),
            FilledButton(
              onPressed: c.busy
                  ? null
                  : () {
                      if (inviteForm.currentState!.validate()) {
                        c.createInvitation(email.text);
                      }
                    },
              child: const Text('Davet oluştur'),
            ),
            if (c.createdInvite case final created?)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Kodu şimdi kopyalayın. Bu ekran kapandığında ham kod yeniden gösterilemez.',
                      ),
                      SelectableText(created.code),
                      Text('Son kabul: ${expiryLabel(created.expiresAt)}'),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: created.code),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Davet kodu kopyalandı.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Davet kodunu kopyala'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Bekleyen davetler',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (!c.loadingDetails && c.pendingInvites.isEmpty)
              const Text('Bekleyen davet yok.'),
            ...c.pendingInvites.map(
              (i) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(i.email),
                      Text('Son kabul: ${expiryLabel(i.expiresAt)}'),
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () async {
                                final yes = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Daveti iptal et'),
                                    content: const Text(
                                      'Bu davet kodu artık kullanılamayacak.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Vazgeç'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('İptal et'),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes == true) {
                                  await c.cancelInvitation(i.id);
                                }
                              },
                        child: const Text('Daveti iptal et'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
