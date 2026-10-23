import 'package:flutter/material.dart';

import 'account_service.dart';

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.demo,
    required this.controller,
    required this.config,
  });
  final Widget demo;
  final AccountController controller;
  final CloudConfig config;
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  bool account = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Column(
      children: [
        Material(
          color: Colors.white,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      widget.controller.focusAccount = false;
                      setState(() => account = false);
                    },
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Demo · Yerel'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => account = true),
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Text('Gerçek hesabım'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: account || widget.controller.focusAccount
              ? AccountPage(
                  controller: widget.controller,
                  config: widget.config,
                )
              : widget.demo,
        ),
      ],
    ),
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.controller,
    required this.config,
  });
  final AccountController controller;
  final CloudConfig config;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final email = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController();
  final form = GlobalKey<FormState>();
  String mode = 'login';
  AccountController get c => widget.controller;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  void changeMode(String value) {
    password.clear();
    repeat.clear();
    c.error = null;
    c.notice = null;
    setState(() => mode = value);
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) {
      return;
    }
    final address = email.text.trim();
    final secret = password.text;
    bool ok;
    if (c.user?.recovery == true) {
      ok = await c.run(
        () => c.gateway.updatePassword(secret),
        success: 'Yeni şifreniz kaydedildi.',
      );
      if (ok) {
        await c.loadTeams();
      }
    } else if (mode == 'signup') {
      ok = await c.run(() => c.gateway.signUp(address, secret));
      if (ok && mounted && c.user == null) {
        setState(() => mode = 'verify');
      }
    } else if (mode == 'reset') {
      ok = await c.run(
        () => c.gateway.reset(address),
        success: 'Adres uygunsa sıfırlama bağlantısı gönderildi. Bağlantıyı bu cihaz ve tarayıcıda açın.',
      );
    } else {
      ok = await c.run(() => c.gateway.signIn(address, secret));
    }
    if (ok) {
      password.clear();
      repeat.clear();
    }
  }

  Future<void> teamDialog({CloudTeam? team}) async {
    final value = TextEditingController(text: team?.name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final key = GlobalKey<FormState>();
        return AlertDialog(
          scrollable: true,
          title: Text(
            team == null ? 'Gerçek ekip oluştur' : 'Ekip adını değiştir',
          ),
          content: Form(
            key: key,
            child: TextFormField(
              controller: value,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Ekip adı'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Ekip adı gerekli.' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) {
                  Navigator.pop(context, value.text);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    // Dialog route exit animation may still use its controller; Flutter owns the field until then.
    if (result != null) {
      await c.saveTeam(result, id: team?.id);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    value.dispose();
  }

  Widget feedback(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: error
              ? Theme.of(context).colorScheme.errorContainer
              : const Color(0xffe4f1ec),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: error
                ? Theme.of(context).colorScheme.onErrorContainer
                : const Color(0xff174c40),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (!widget.config.valid) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.config.configured
                    ? 'Supabase yapılandırması geçersiz. URL, publishable anahtar ve yönlendirme adreslerini kontrol edin. Demo kullanılabilir.'
                    : 'Gerçek hesaplar için Supabase bağlantısını yapılandırın. README kurulum adımlarını içerir. Demo yerel verilerinizle kullanılabilir.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (c.restoring) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Oturum geri yükleniyor…'),
              ],
            ),
          );
        }
        if (!c.ready) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.error ?? 'Hesap bağlantısı açılamadı.'),
                  FilledButton(
                    onPressed: c.start,
                    child: const Text('Bağlantıyı tekrar dene'),
                  ),
                ],
              ),
            ),
          );
        }
        final recovery = c.user?.recovery == true;
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Gerçek hesap',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Supabase hesabınız ve size ait ekipler. Yerel Demo kayıtları buraya aktarılmaz.',
                  ),
                  if (c.error != null) feedback(c.error!, error: true),
                  if (c.notice != null) feedback(c.notice!),
                  if (c.busy || c.loadingTeams) const LinearProgressIndicator(),
                  const SizedBox(height: 20),
                  if (c.user != null && !recovery) ...[
                    Text(
                      c.user!.email,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: c.busy ? null : c.signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Çıkış yap'),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Ekiplerim',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: c.busy ? null : () => teamDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Ekip oluştur'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.busy || c.loadingTeams
                              ? null
                              : c.loadTeams,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Yenile'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (!c.loadingTeams && c.teams.isEmpty)
                      const Text(
                        'Henüz görünür bir ekibiniz yok. İlk ekibinizi oluşturabilirsiniz.',
                      ),
                    ...c.teams.map(
                      (team) => Card(
                        child: ListTile(
                          title: Text(team.name),
                          trailing: IconButton(
                            tooltip: 'Ekip adını değiştir',
                            onPressed: c.busy
                                ? null
                                : () => teamDialog(team: team),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Çalışan daveti ve ortak vardiya planı sonraki aşamada bağlanacak.',
                    ),
                  ] else if (mode == 'verify' && !recovery) ...[
                    Text(
                      'E-postanızı doğrulayın',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Adres uygunsa doğrulama bağlantısı gönderildi. E-postadaki bağlantıyı işlemi başlattığınız cihaz ve tarayıcıda açın. Ardından giriş yapabilirsiniz.',
                    ),
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.run(
                              () => c.gateway.resend(email.text.trim()),
                              success: 'Adres uygunsa doğrulama bağlantısı yeniden gönderildi.',
                            ),
                      child: const Text('Doğrulama e-postasını yeniden gönder'),
                    ),
                    TextButton(
                      onPressed: () => changeMode('login'),
                      child: const Text('Giriş ekranına dön'),
                    ),
                  ] else
                    Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            recovery
                                ? 'Yeni şifre belirleyin'
                                : mode == 'signup'
                                ? 'Hesap oluştur'
                                : mode == 'reset'
                                ? 'Şifremi unuttum'
                                : 'Giriş yap',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 20),
                          if (!recovery)
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'E-posta',
                              ),
                              validator: (v) =>
                                  v == null ||
                                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(v.trim())
                                  ? 'Geçerli bir e-posta girin.'
                                  : null,
                            ),
                          if (mode != 'reset' || recovery) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: password,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Şifre',
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Şifre gerekli.'
                                  : (recovery || mode == 'signup') &&
                                        v.length < 8
                                  ? 'En az 8 karakter kullanın.'
                                  : null,
                            ),
                            if (recovery || mode == 'signup') ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: repeat,
                                obscureText: true,
                                enableSuggestions: false,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Şifre tekrarı',
                                ),
                                validator: (v) => v != password.text
                                    ? 'Şifreler eşleşmiyor.'
                                    : null,
                              ),
                            ],
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: c.busy ? null : submit,
                            child: Text(
                              recovery
                                  ? 'Yeni şifreyi kaydet'
                                  : mode == 'signup'
                                  ? 'Kayıt ol'
                                  : mode == 'reset'
                                  ? 'Sıfırlama bağlantısı gönder'
                                  : 'Giriş yap',
                            ),
                          ),
                          if (!recovery) ...[
                            TextButton(
                              onPressed: c.busy
                                  ? null
                                  : () => changeMode(
                                      mode == 'signup' ? 'login' : 'signup',
                                    ),
                              child: Text(
                                mode == 'signup'
                                    ? 'Zaten hesabım var'
                                    : 'Yeni hesap oluştur',
                              ),
                            ),
                            TextButton(
                              onPressed: c.busy
                                  ? null
                                  : () => changeMode(
                                      mode == 'reset' ? 'login' : 'reset',
                                    ),
                              child: Text(
                                mode == 'reset'
                                    ? 'Giriş ekranına dön'
                                    : 'Şifremi unuttum',
                              ),
                            ),
                            TextButton(
                              onPressed: c.busy
                                  ? null
                                  : () {
                                      if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(email.text.trim())) {
                                        changeMode('verify');
                                      } else {
                                        c.error =
                                            'Önce geçerli bir e-posta girin.';
                                        c.emit();
                                      }
                                    },
                              child: const Text(
                                'Doğrulama bağlantısını yeniden iste',
                              ),
                            ),
                          ] else
                            TextButton(
                              onPressed: c.busy ? null : c.signOut,
                              child: const Text('İptal et ve çıkış yap'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
