begin;
create extension if not exists pgtap with schema extensions;
select plan(15);
insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000001','a@example.invalid'),
 ('10000000-0000-0000-0000-000000000002','b@example.invalid');
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select public.create_team('A ekibi') as team_a \gset
select is((select count(*) from public.teams),1::bigint,'A sees own team');
select is((select role from public.team_members where team_id=:'team_a'),'owner','creator is owner atomically');
select lives_ok(format('select public.rename_team(%L,''A yeni'')', :'team_a'),'owner can rename');
select is((select name from public.teams where id=:'team_a'),'A yeni','rename persisted');
select throws_ok('select public.create_team('' '')','22023',null,'invalid creation rejected');
select is((select count(*) from public.teams),1::bigint,'invalid creation leaves no team');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*) from public.teams where id=:'team_a'),0::bigint,'B cannot read A by known id');
select is((select count(*) from public.team_members where team_id=:'team_a'),0::bigint,'B cannot read A membership');
select throws_ok(format('select public.rename_team(%L,''hacked'')', :'team_a),'42501',null,'B cannot rename A via RPC');
select throws_ok(format('update public.teams set name=''hacked'' where id=%L', :'team_a),'42501',null,'B cannot directly write teams');
select throws_ok(format('insert into public.team_members values(%L,%L,''owner'')', :'team_a','10000000-0000-0000-0000-000000000002'),'42501',null,'B cannot grant own membership');
select public.create_team('B ekibi') as team_b \gset
select is((select count(*) from public.teams),1::bigint,'B only sees B team');
select throws_ok('update public.team_members set role=''owner''','42501',null,'client cannot escalate roles');
set local role anon;
select throws_ok('select * from public.teams','42501',null,'anonymous cannot read teams');
select throws_ok('select public.create_team(''anonymous'')','42501',null,'anonymous cannot create');
select * from finish();
rollback;
