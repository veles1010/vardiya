import 'dart:async';

import '../domain.dart';
import 'plan_model.dart';
import 'leave_model.dart';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'callback_location.dart'
    if (dart.library.js_interop) 'callback_location_web.dart';

class AccountIdentity {
  const AccountIdentity(
    this.id,
    this.email, {
    this.recovery = false,
    this.fromLink = false,
  });
  final String id, email;
  final bool recovery, fromLink;
}

class CloudTeam {
  const CloudTeam(this.id, this.name, {this.role = 'employee'});
  final String id, name, role;
  bool get canManage => role == 'owner' || role == 'manager';
}

class CloudMember {
  const CloudMember(this.id, this.email, this.role);
  final String id, email, role;
}

class PendingInvite {
  const PendingInvite(this.id, this.email, this.expiresAt);
  final String id, email;
  final DateTime expiresAt;
}

class CreatedInvite {
  const CreatedInvite(this.id, this.code, this.expiresAt);
  final String id, code;
  final DateTime expiresAt;
}

class InvitePreview {
  const InvitePreview(this.teamId, this.teamName, this.expiresAt);
  final String teamId, teamName;
  final DateTime expiresAt;
}

abstract interface class AccountGateway {
  Stream<AccountIdentity?> get changes;
  Future<AccountIdentity?> initialize();
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resend(String email);
  Future<void> reset(String email);
  Future<void> updatePassword(String password);
  Future<void> signOut();
  Future<List<CloudTeam>> teams();
  Future<void> createTeam(String name);
  Future<void> renameTeam(String id, String name);
  Future<List<CloudMember>> members(String teamId);
  Future<List<PendingInvite>> invitations(String teamId);
  Future<CreatedInvite> createInvitation(String teamId, String email);
  Future<void> cancelInvitation(String id);
  Future<InvitePreview> previewInvitation(String code);
  Future<void> acceptInvitation(String code);
  Future<CloudPlan> readPlan(String teamId, {required bool draft});
  Future<void> saveShift(
    String teamId,
    int version,
    Shift shift, {
    required bool creating,
  });
  Future<void> deleteShift(String teamId, int version, String shiftId);
  Future<void> publishPlan(String teamId, int version);
  Future<LeaveInbox> readLeaves(String teamId);
  Future<void> createLeave(
    String teamId,
    int version,
    DateTime start,
    DateTime end,
    String description,
  );
  Future<void> actOnLeave(
    String teamId,
    int version,
    String requestId,
    int revision,
    String action,
    String reason,
  );
  void dispose();
}

class CloudConfig {
  const CloudConfig({
    this.url = const String.fromEnvironment('SUPABASE_URL'),
    this.key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    this.webRedirect = const String.fromEnvironment(
      'AUTH_WEB_REDIRECT_URL',
      defaultValue: 'http://127.0.0.1:7357/',
    ),
    this.mobileRedirect = const String.fromEnvironment(
      'AUTH_MOBILE_REDIRECT_URL',
      defaultValue: 'com.vardiya.app://auth/callback',
    ),
  });
  final String url, key, webRedirect, mobileRedirect;
  bool get configured => url.isNotEmpty || key.isNotEmpty;
  bool get valid {
    final u = Uri.tryParse(url);
    final w = Uri.tryParse(webRedirect);
    final m = Uri.tryParse(mobileRedirect);
    return u != null &&
        u.host.isNotEmpty &&
        (u.scheme == 'https' ||
            (u.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(u.host))) &&
        key.startsWith('sb_publishable_') &&
        !key.contains('REPLACE') &&
        w != null &&
        ['http', 'https'].contains(w.scheme) &&
        w.host.isNotEmpty &&
        m != null &&
        m.hasScheme;
  }

  String get redirect => kIsWeb ? webRedirect : mobileRedirect;
}

class SupabaseAccountGateway implements AccountGateway {
  SupabaseAccountGateway(this.config);
  final CloudConfig config;
  final _events = StreamController<AccountIdentity?>.broadcast();
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<Uri>? _links;
  final _appLinks = AppLinks();
  late SupabaseClient _client;
  bool _recovery = false;
  bool _initialHandled = false;
  final _preferences = SharedPreferencesAsync();
  static const _recoveryKey = 'vardiya.auth.pending_recovery_user';
  @override
  Stream<AccountIdentity?> get changes => _events.stream;
  AccountIdentity? get identity {
    final user = _client.auth.currentUser;
    return user == null
        ? null
        : AccountIdentity(user.id, user.email ?? '', recovery: _recovery);
  }

  @override
  Future<AccountIdentity?> initialize() async {
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: false,
      ),
    );
    _client = Supabase.instance.client;
    await _auth?.cancel();
    await _links?.cancel();
    final pending = await _preferences.getString(_recoveryKey);
    _recovery = pending != null && pending == _client.auth.currentUser?.id;
    _auth = _client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _recovery = true;
        }
        if (state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.signedIn) {
          _recovery = false;
        }
        _events.add(identity);
      },
      onError: (Object e) {
        _events.addError(e);
      },
    );
    if (_client.auth.currentSession?.isExpired ?? false) {
      await _client.auth.refreshSession();
    }
    if (kIsWeb) {
      await handleLink(Uri.base);
    } else {
      _links = _appLinks.uriLinkStream.listen((uri) {
        unawaited(
          handleLink(uri).catchError((Object e) {
            _events.addError(e);
          }),
        );
      });
      if (!_initialHandled) {
        _initialHandled = true;
        final initial = await _appLinks.getInitialLink();
        if (initial != null) {
          await handleLink(initial);
        }
      }
    }
    return identity;
  }

  Future<void> handleLink(Uri uri) async {
    final expected = Uri.parse(config.redirect);
    if (uri.scheme != expected.scheme ||
        uri.host != expected.host ||
        uri.port != expected.port ||
        uri.path != expected.path) {
      return;
    }
    final params = {
      ...uri.queryParameters,
      ...Uri.splitQueryString(uri.fragment),
    };
    if (!params.containsKey('code') &&
        !params.containsKey('access_token') &&
        !params.containsKey('error') &&
        !params.containsKey('error_code') &&
        !params.containsKey('error_description')) {
      return;
    }
    try {
      await _client.auth.getSessionFromUrl(uri);
      if (_recovery && _client.auth.currentUser != null) {
        await _preferences.setString(
          _recoveryKey,
          _client.auth.currentUser!.id,
        );
      }
      final user = identity;
      if (user != null) {
        _events.add(
          AccountIdentity(
            user.id,
            user.email,
            recovery: _recovery,
            fromLink: true,
          ),
        );
      }
    } finally {
      if (kIsWeb) {
        clearCallbackUrl();
      }
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: config.redirect,
    );
  }

  @override
  Future<void> resend(String email) => _client.auth.resend(
    type: OtpType.signup,
    email: email,
    emailRedirectTo: config.redirect,
  );
  @override
  Future<void> reset(String email) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: config.redirect);
  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
    _recovery = false;
    await _preferences.remove(_recoveryKey);
    _events.add(identity);
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut(scope: SignOutScope.local);
    await _preferences.remove(_recoveryKey);
  }

  @override
  Future<List<CloudTeam>> teams() async {
    final rows = await _client
        .from('teams')
        .select('id,name,team_members!inner(user_id,role)')
        .eq('team_members.user_id', _client.auth.currentUser!.id)
        .order('created_at');
    return rows
        .map(
          (r) => CloudTeam(
            r['id'] as String,
            r['name'] as String,
            role: (r['team_members'] as List).single['role'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> createTeam(String name) async {
    await _client.rpc('create_team', params: {'team_name': name});
  }

  @override
  Future<void> renameTeam(String id, String name) async {
    await _client.rpc(
      'rename_team',
      params: {'target_team': id, 'team_name': name},
    );
  }

  @override
  Future<List<CloudMember>> members(String teamId) async {
    final rows = await _client.rpc(
      'list_team_members',
      params: {'target_team': teamId},
    );
    return (rows as List)
        .map((r) => CloudMember(r['user_id'], r['email'], r['role']))
        .toList();
  }

  @override
  Future<List<PendingInvite>> invitations(String teamId) async {
    final rows = await _client.rpc(
      'list_team_invitations',
      params: {'target_team': teamId},
    );
    return (rows as List)
        .map(
          (r) => PendingInvite(
            r['id'],
            r['target_email'],
            DateTime.parse(r['expires_at']),
          ),
        )
        .toList();
  }

  @override
  Future<CreatedInvite> createInvitation(String teamId, String email) async {
    final rows = await _client.rpc(
      'create_team_invitation',
      params: {'target_team': teamId, 'invite_email': email},
    );
    final r = (rows as List).single;
    return CreatedInvite(
      r['invitation_id'],
      r['code'],
      DateTime.parse(r['expires_at']),
    );
  }

  @override
  Future<void> cancelInvitation(String id) async {
    await _client.rpc(
      'cancel_team_invitation',
      params: {'target_invitation': id},
    );
  }

  @override
  Future<InvitePreview> previewInvitation(String code) async {
    final rows = await _client.rpc(
      'preview_team_invitation',
      params: {'invite_code': code},
    );
    final r = (rows as List).single;
    return InvitePreview(
      r['team_id'],
      r['team_name'],
      DateTime.parse(r['expires_at']),
    );
  }

  @override
  Future<void> acceptInvitation(String code) async {
    await _client.rpc('accept_team_invitation', params: {'invite_code': code});
  }

  @override
  Future<CloudPlan> readPlan(String teamId, {required bool draft}) async {
    final data = await _client.rpc(
      'read_team_plan',
      params: {'target_team': teamId, 'draft': draft},
    );
    return CloudPlan.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> saveShift(
    String teamId,
    int version,
    Shift shift, {
    required bool creating,
  }) async {
    await _client.rpc(
      'save_team_shift',
      params: {
        'target_team': teamId,
        'expected_version': version,
        'target_shift': creating ? null : shift.id,
        'assigned_user': shift.employeeId,
        'shift_start': planTime(shift.start),
        'shift_end': planTime(shift.end),
        'unpaid_break': shift.breakMinutes,
        'shift_label': shift.label.trim(),
        'shift_note': shift.note,
      },
    );
  }

  @override
  Future<void> deleteShift(String teamId, int version, String shiftId) async {
    await _client.rpc(
      'delete_team_shift',
      params: {
        'target_team': teamId,
        'expected_version': version,
        'target_shift': shiftId,
      },
    );
  }

  @override
  Future<void> publishPlan(String teamId, int version) async {
    await _client.rpc(
      'publish_team_plan',
      params: {'target_team': teamId, 'expected_version': version},
    );
  }

  @override
  Future<LeaveInbox> readLeaves(String teamId) async {
    final data = await _client.rpc(
      'read_team_leaves',
      params: {'target_team': teamId},
    );
    return LeaveInbox.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> createLeave(
    String teamId,
    int version,
    DateTime start,
    DateTime end,
    String description,
  ) async {
    await _client.rpc(
      'create_team_leave',
      params: {
        'target_team': teamId,
        'expected_version': version,
        'first_day': leaveDate(start),
        'last_day': leaveDate(end),
        'explanation': description.trim(),
      },
    );
  }

  @override
  Future<void> actOnLeave(
    String teamId,
    int version,
    String requestId,
    int revision,
    String action,
    String reason,
  ) async {
    await _client.rpc(
      'act_on_team_leave',
      params: {
        'target_team': teamId,
        'expected_version': version,
        'target_request': requestId,
        'expected_revision': revision,
        'action': action,
        'reason': reason.trim(),
      },
    );
  }

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    unawaited(_links?.cancel());
    unawaited(_events.close());
  }
}

String accountError(Object e) {
  if (e is AuthException) {
    return switch (e.code) {
      'invalid_credentials' => 'E-posta veya şifre geçersiz.',
      'email_not_confirmed' => 'Girişten önce e-postanızı doğrulayın.',
      'otp_expired' ||
      'flow_state_expired' ||
      'flow_state_not_found' ||
      'bad_code_verifier' => 'Bağlantı geçersiz veya süresi dolmuş. Yeni bağlantı isteyin; bağlantıyı işlemi başlattığınız cihaz ve tarayıcıda açın.',
      'over_email_send_rate_limit' || 'over_request_rate_limit' =>
        'Çok sık deneme yapıldı. Bir süre sonra tekrar deneyin.',
      'weak_password' => 'Daha güçlü bir şifre seçin (en az 8 karakter).',
      _ => 'İşlem tamamlanamadı. Bağlantı süresi dolmuş olabilir; bilgilerinizi kontrol edip yeniden deneyin.',
    };
  }
  if (e is PostgrestException) {
    if (e.code == 'P1001') {
      return 'Vardiya onaylanmış izinle çakışıyor. İzin günlerine vardiya atanamaz.';
    }
    if (e.code == 'P1002') {
      return 'İzin, taslak veya yayımlanmış vardiyayla çakışıyor. Planı düzenleyip yeniden yayımlayın; talepleri yenileyin.';
    }
    if (e.code == 'P1003') {
      return 'Bu günlerde bekleyen veya onaylanmış başka izin talebiniz var.';
    }
    if (e.code == '40001') {
      return 'Plan veya talep başka bir işlemle değişti. Yenile düğmesiyle güncel veriyi alın; işlemi yeniden yapın.';
    }
    if (e.code == '23P01') {
      return 'Bu üyenin aynı saatte başka bir taslak vardiyası var. Tarih ve saatleri kontrol edin.';
    }
    return e.code == '42501'
        ? 'İşlem yetkiniz yok veya davet geçersiz. Davetin hedef e-postasıyla doğrulanmış hesabı kullanın; davet süresi dolmuş, iptal edilmiş ya da kullanılmış olabilir.'
        : e.code == '22023'
        ? 'Geçerli alanlar girin. Bitiş başlangıçtan sonra, mola 0 ile toplam süre arasında olmalı; atanan kişi ekip üyesi olmalı.'
        : 'Ekip işlemi tamamlanamadı. Bağlantınızı ve veritabanı kurulumunu kontrol edin.';
  }
  return 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
}

String leaveError(Object e) {
  if (e is PostgrestException && e.code == '42501') {
    return 'Bu ekipte bu izin işlemi için yetkiniz yok. Kendi hesabınızı ve ekip rolünüzü kontrol edin.';
  }
  if (e is PostgrestException && e.code == '22023') {
    return 'Bitiş günü başlangıçtan önce olamaz. Açıklama ve gerekçe en fazla 500 karakter olmalı; ret ve onaylı izin iptalinde gerekçe gerekir.';
  }
  return accountError(e);
}

class AccountController extends ChangeNotifier {
  AccountController(this.gateway);
  final AccountGateway gateway;
  AccountIdentity? user;
  List<CloudTeam> teams = const [];
  CloudTeam? selectedTeam;
  List<CloudMember> teamMembers = const [];
  List<PendingInvite> pendingInvites = const [];
  CreatedInvite? createdInvite;
  InvitePreview? invitePreview;
  String? _previewCode;
  LeaveInbox? leaveInbox;
  bool loadingLeaves = false, leavesStale = false;
  int _leaveGeneration = 0;
  CloudPlan? plan;
  bool loadingPlan = false, planDraft = false, planStale = false;
  int _planGeneration = 0;
  bool loadingDetails = false;
  int _detailGeneration = 0;
  int _previewGeneration = 0;
  void clearTeamDetails() {
    _detailGeneration++;
    _leaveGeneration++;
    leaveInbox = null;
    loadingLeaves = false;
    leavesStale = false;
    _planGeneration++;
    plan = null;
    loadingPlan = false;
    planStale = false;
    selectedTeam = null;
    teamMembers = const [];
    pendingInvites = const [];
    createdInvite = null;
    loadingDetails = false;
  }

  void clearInvitationPreview() {
    _previewGeneration++;
    invitePreview = null;
    _previewCode = null;
    emit();
  }

  bool ready = false;
  bool restoring = true,
      busy = false,
      loadingTeams = false,
      focusAccount = false;
  String? error, notice;
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<AccountIdentity?>? _subscription;
  void emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> start() async {
    restoring = true;
    error = null;
    emit();
    _subscription ??= gateway.changes.listen(
      _accept,
      onError: (Object e) {
        error = accountError(e);
        focusAccount = true;
        emit();
      },
    );
    try {
      _accept(await gateway.initialize().timeout(const Duration(seconds: 30)));
      ready = true;
    } catch (e) {
      error = accountError(e);
      focusAccount = true;
    } finally {
      restoring = false;
      emit();
    }
  }

  void _accept(AccountIdentity? next) {
    if (_disposed) {
      return;
    }
    final changed = user?.id != next?.id;
    if (changed || next == null) {
      _generation++;
      teams = const [];
      clearTeamDetails();
      invitePreview = null;
      _previewCode = null;
      loadingTeams = false;
      notice = null;
    }
    user = next;
    if (next?.recovery == true || next?.fromLink == true) {
      focusAccount = true;
    }
    emit();
    if (next != null && changed && !next.recovery) {
      unawaited(loadTeams());
    }
  }

  Future<void> loadTeams() async {
    if (user == null) {
      return;
    }
    final epoch = _generation;
    loadingTeams = true;
    error = null;
    emit();
    try {
      final result = await gateway.teams().timeout(const Duration(seconds: 30));
      if (epoch == _generation && !_disposed) {
        teams = List.unmodifiable(result);
      }
    } catch (e) {
      if (epoch == _generation) {
        error = accountError(e);
      }
    } finally {
      if (epoch == _generation) {
        loadingTeams = false;
        emit();
      }
    }
  }

  Future<bool> run(
    Future<void> Function() action, {
    String? success,
    String Function(Object)? errorMessage,
  }) async {
    if (busy) {
      return false;
    }
    final epoch = _generation;
    busy = true;
    error = null;
    notice = null;
    emit();
    try {
      await action().timeout(const Duration(seconds: 30));
      if (epoch == _generation) {
        notice = success;
      }
      return true;
    } catch (e) {
      if (epoch == _generation) {
        error = (errorMessage ?? accountError)(e);
      }
      return false;
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> signOut() async {
    // Invalidate cached/in-flight tenant data before contacting the server.
    _generation++;
    teams = const [];
    clearTeamDetails();
    invitePreview = null;
    _previewCode = null;
    loadingTeams = false;
    emit();
    await run(gateway.signOut);
  }

  Future<void> saveTeam(String name, {String? id}) async {
    if (name.trim().isEmpty || name.trim().length > 100) {
      error = 'Ekip adı 1–100 karakter olmalı.';
      emit();
      return;
    }
    final epoch = _generation;
    if (await run(
      () => id == null
          ? gateway.createTeam(name.trim())
          : gateway.renameTeam(id, name.trim()),
    )) {
      if (epoch == _generation) {
        await loadTeams();
      }
    }
  }

  Future<void> openTeam(CloudTeam team) async {
    clearTeamDetails();
    selectedTeam = team;
    await loadDetails();
  }

  Future<void> loadDetails() async {
    final team = selectedTeam;
    if (team == null || user == null) {
      return;
    }
    final epoch = _generation, detail = ++_detailGeneration;
    loadingDetails = true;
    error = null;
    emit();
    try {
      final results = await Future.wait<Object>([
        gateway.members(team.id),
        team.canManage
            ? gateway.invitations(team.id)
            : Future.value(<PendingInvite>[]),
      ]).timeout(const Duration(seconds: 30));
      if (epoch == _generation && detail == _detailGeneration && !_disposed) {
        teamMembers = List.unmodifiable(results[0] as List<CloudMember>);
        pendingInvites = List.unmodifiable(results[1] as List<PendingInvite>);
      }
    } catch (e) {
      if (epoch == _generation && detail == _detailGeneration) {
        error = accountError(e);
      }
    } finally {
      if (epoch == _generation && detail == _detailGeneration) {
        loadingDetails = false;
        emit();
      }
    }
  }

  Future<void> createInvitation(String email) async {
    final team = selectedTeam;
    if (team == null) {
      return;
    }
    final epoch = _generation;
    createdInvite = null;
    final ok = await run(() async {
      final result = await gateway.createInvitation(team.id, email.trim());
      if (epoch == _generation && selectedTeam?.id == team.id && !_disposed) {
        createdInvite = result;
      }
    });
    if (ok && epoch == _generation && selectedTeam?.id == team.id) {
      await loadDetails();
    }
  }

  Future<void> cancelInvitation(String id) async {
    final epoch = _generation, teamId = selectedTeam?.id;
    if (await run(
      () => gateway.cancelInvitation(id),
      success: 'Davet iptal edildi.',
    )) {
      if (epoch == _generation && selectedTeam?.id == teamId) {
        if (createdInvite?.id == id) {
          createdInvite = null;
        }
        await loadDetails();
      }
    }
  }

  Future<void> previewInvitation(String code) async {
    invitePreview = null;
    _previewCode = null;
    final epoch = _generation, preview = ++_previewGeneration;
    await run(() async {
      final result = await gateway.previewInvitation(code.trim());
      if (epoch == _generation && preview == _previewGeneration && !_disposed) {
        invitePreview = result;
        _previewCode = code.trim();
      }
    });
  }

  Future<void> acceptInvitation() async {
    final code = _previewCode;
    if (code == null || invitePreview == null) {
      return;
    }
    final epoch = _generation;
    if (await run(
      () => gateway.acceptInvitation(code),
      success: 'Ekibe çalışan olarak katıldınız.',
    )) {
      if (epoch == _generation) {
        invitePreview = null;
        _previewCode = null;
        await loadTeams();
      }
    } else {
      clearInvitationPreview();
    }
  }

  Future<void> loadPlan({bool? draft}) async {
    final team = selectedTeam;
    if (team == null || user == null) return;
    final epoch = _generation, request = ++_planGeneration;
    planDraft = team.canManage && (draft ?? planDraft);
    plan = null;
    loadingPlan = true;
    error = null;
    emit();
    try {
      final result = await gateway
          .readPlan(team.id, draft: planDraft)
          .timeout(const Duration(seconds: 30));
      if (epoch == _generation && request == _planGeneration && !_disposed) {
        plan = result;
        planStale = false;
      }
    } catch (e) {
      if (epoch == _generation && request == _planGeneration) {
        error = accountError(e);
      }
    } finally {
      if (epoch == _generation && request == _planGeneration) {
        loadingPlan = false;
        emit();
      }
    }
  }

  Future<bool> changePlan(Future<void> Function(String, int) action) async {
    final team = selectedTeam, snapshot = plan;
    if (team == null ||
        !team.canManage ||
        snapshot == null ||
        !planDraft ||
        planStale) {
      return false;
    }
    final epoch = _generation, request = _planGeneration;
    final ok = await run(() => action(team.id, snapshot.version));
    if (epoch != _generation || request != _planGeneration || _disposed) {
      return false;
    }
    if (ok) {
      await loadPlan();
    } else {
      // A timeout can also mean the transaction committed; require refresh before any retry.
      planStale = true;
      emit();
    }
    return ok;
  }

  Future<bool> savePlanShift(Shift shift, {required bool creating}) =>
      changePlan(
        (team, version) =>
            gateway.saveShift(team, version, shift, creating: creating),
      );
  Future<bool> deletePlanShift(String id) =>
      changePlan((team, version) => gateway.deleteShift(team, version, id));
  Future<bool> publishPlan() => changePlan(gateway.publishPlan);

  Future<void> loadLeaves() async {
    final team = selectedTeam;
    if (team == null || user == null) return;
    final epoch = _generation, request = ++_leaveGeneration;
    loadingLeaves = true;
    leaveInbox = null;
    error = null;
    emit();
    try {
      final result = await gateway
          .readLeaves(team.id)
          .timeout(const Duration(seconds: 30));
      if (epoch == _generation && request == _leaveGeneration && !_disposed) {
        leaveInbox = result;
        leavesStale = false;
      }
    } catch (e) {
      if (epoch == _generation && request == _leaveGeneration) {
        error = leaveError(e);
      }
    } finally {
      if (epoch == _generation && request == _leaveGeneration) {
        loadingLeaves = false;
        emit();
      }
    }
  }

  Future<bool> changeLeave(Future<void> Function(String, int) action) async {
    final team = selectedTeam, snapshot = leaveInbox;
    if (team == null ||
        user == null ||
        snapshot == null ||
        loadingLeaves ||
        leavesStale ||
        busy) {
      return false;
    }
    final epoch = _generation, request = _leaveGeneration;
    final ok = await run(
      () => action(team.id, snapshot.version),
      errorMessage: leaveError,
    );
    if (epoch != _generation || request != _leaveGeneration || _disposed) {
      return false;
    }
    if (ok) {
      // All leave writes advance the shared team version. Cached plans must be refreshed.
      _planGeneration++;
      plan = null;
      loadingPlan = false;
      planStale = true;
      await loadLeaves();
    } else {
      leavesStale = true;
      emit();
    }
    return ok;
  }

  Future<bool> createLeave(DateTime start, DateTime end, String description) =>
      changeLeave(
        (team, version) =>
            gateway.createLeave(team, version, start, end, description),
      );
  Future<bool> actOnLeave(LeaveRequest r, String action, String reason) =>
      changeLeave(
        (team, version) =>
            gateway.actOnLeave(team, version, r.id, r.revision, action, reason),
      );

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription?.cancel());
    gateway.dispose();
    super.dispose();
  }
}
