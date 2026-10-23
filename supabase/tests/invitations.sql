begin;
create extension if not exists pgtap with schema extensions;
select plan(33);
insert into auth.users(id,email,email_confirmed_at) values
 ('20000000-0000-0000-0000-000000000001','owner@example.invalid',now()),
 ('20000000-0000-0000-0000-000000000002','worker@example.invalid',now()),
 ('20000000-0000-0000-0000-000000000003','other@example.invalid',now()),
 ('20000000-0000-0000-0000-000000000004','unverified@example.invalid',null),
 ('20000000-0000-0000-0000-000000000005','manager@example.invalid',now());
set local role authenticated;
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000001"}';
select public.create_team('Invite team') as team_a \gset
select * from public.create_team_invitation(:'team_a',' Worker@Example.Invalid ') \gset first_
select is(length(:'first_code'),64,'code contains 256 random bits');
select * from public.create_team_invitation(:'team_a','worker@example.invalid') \gset second_
select ok(:'first_code' <> :'second_code','codes are distinct');
select is((select count(*) from public.list_team_invitations(:'team_a')),2::bigint,'owner sees pending invites');
select throws_ok('select * from public.team_invitations','42501',null,'no direct invite reads or hashes');
select throws_ok(format('insert into public.team_invitations(team_id) values(%L)',:'team_a'),'42501',null,'no direct invite writes');
select throws_ok(format('select public.create_team_invitation(%L,''bad'')',:'team_a'),'22023',null,'email validated');
reset role;
select is((select code_hash from public.team_invitations where id=:'first_invitation_id'),extensions.digest(:'first_code','sha256'),'only code digest stored');
select ok((select expires_at-created_at between interval '7 days' - interval '1 second' and interval '7 days' + interval '1 second' from public.team_invitations where id=:'first_invitation_id'),'expires in seven server days');
insert into public.team_members values(:'team_a','20000000-0000-0000-0000-000000000005','manager');
set local role authenticated;
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000005"}';
select * from public.create_team_invitation(:'team_a','unverified@example.invalid') \gset unverified_
select lives_ok(format('select public.cancel_team_invitation(%L)',:'second_invitation_id'),'manager can cancel');
select is((select count(*) from public.list_team_members(:'team_a')),2::bigint,'members list contains roles');
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000003","email":"worker@example.invalid","email_verified":true}';
select public.create_team('Other team') as team_b \gset
select throws_ok(format('select public.create_team_invitation(%L,''worker@example.invalid'')',:'team_a'),'42501',null,'other owner cannot invite into A');
select throws_ok(format('select * from public.list_team_invitations(%L)',:'team_a'),'42501',null,'outsider cannot list invites');
select throws_ok(format('select * from public.list_team_members(%L)',:'team_a'),'42501',null,'outsider cannot list members');
select throws_ok(format('select * from public.preview_team_invitation(%L)',:'first_code'),'42501',null,'forged JWT email cannot preview');
select throws_ok(format('select public.accept_team_invitation(%L)',:'first_code'),'42501',null,'wrong actual email cannot accept');
select throws_ok(format('select public.cancel_team_invitation(%L)',:'first_invitation_id'),'42501',null,'other team owner cannot cancel');
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000004","email_verified":true}';
select throws_ok(format('select * from public.preview_team_invitation(%L)',:'unverified_code'),'42501',null,'unverified Auth account cannot preview');
select throws_ok(format('select public.accept_team_invitation(%L)',:'unverified_code'),'42501',null,'unverified Auth account cannot accept');
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000002"}';
select is((select team_name from public.preview_team_invitation(:'first_code')),'Invite team','target previews team before accepting');
select is((select count(*) from public.team_members where team_id=:'team_a'),0::bigint,'preview grants no membership');
select throws_ok(format('select public.accept_team_invitation(%L)',:'second_code'),'42501',null,'cancelled invitation rejected');
select is(public.accept_team_invitation(:'first_code'),:'team_a'::uuid,'verified target accepts');
select is((select role from public.team_members where team_id=:'team_a' and user_id=auth.uid()),'employee','only employee granted');
select throws_ok(format('select public.accept_team_invitation(%L)',:'first_code'),'42501',null,'second accept rejected');
select is((select count(*) from public.team_members where team_id=:'team_a' and user_id=auth.uid()),1::bigint,'double accept never duplicates membership');
select throws_ok(format('select public.create_team_invitation(%L,''other@example.invalid'')',:'team_a'),'42501',null,'employee cannot invite');
select throws_ok(format('select * from public.list_team_invitations(%L)',:'team_a'),'42501',null,'employee cannot read pending invites');
select throws_ok('update public.team_members set role=''manager''','42501',null,'employee cannot escalate role');
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000001"}';
select * from public.create_team_invitation(:'team_a','worker@example.invalid') \gset repeat_
select * from public.create_team_invitation(:'team_a','worker@example.invalid') \gset expired_
reset role;
update public.team_invitations set expires_at=clock_timestamp()-interval '1 second' where id=:'expired_invitation_id';
set local role authenticated;
set local request.jwt.claims = '{"sub":"20000000-0000-0000-0000-000000000002"}';
select throws_ok(format('select public.accept_team_invitation(%L)',:'expired_code'),'42501',null,'expired invitation rejected');
select lives_ok(format('select public.accept_team_invitation(%L)',:'repeat_code'),'already member valid invite consumed without duplicate');
select is((select count(*) from public.team_members where team_id=:'team_a' and user_id=auth.uid()),1::bigint,'existing membership remains unique');
select throws_ok(format('select * from public.preview_team_invitation(%L)',:'repeat_code'),'42501',null,'used invite cannot be previewed');
set local role anon;
select throws_ok(format('select public.accept_team_invitation(%L)',:'first_code'),'42501',null,'anonymous cannot accept');
select * from finish();
rollback;
