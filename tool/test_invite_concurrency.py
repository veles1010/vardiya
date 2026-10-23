"""Two genuinely concurrent PostgreSQL sessions; disposable CI database only.
No remote URL, credentials or invitation code is accepted or printed.
"""
import concurrent.futures
import json
import subprocess
import threading

CONTAINER = 'supabase_db_vardiya'
OWNER = '30000000-0000-0000-0000-000000000001'
WORKER = '30000000-0000-0000-0000-000000000002'

def sql(query):
    return subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=query, text=True, capture_output=True, timeout=45)

def require(result):
    if result.returncode:
        # Deliberately do not print SQL, stdout or stderr (may include a code).
        raise RuntimeError('Concurrency test database operation failed; inspect the isolated database setup.')
    return result.stdout.strip()

def claims(user):
    return "set local role authenticated; set local request.jwt.claims = '" + json.dumps({'sub': user}) + "';"

def main():
    setup = f"""
    insert into auth.users(id,email,email_confirmed_at) values
      ('{OWNER}','race-owner@example.invalid',now()), ('{WORKER}','race-worker@example.invalid',now());
    begin;
    {claims(OWNER)}
    select public.create_team('Concurrent test team') as team_id \gset
    select code from public.create_team_invitation(:'team_id','race-worker@example.invalid');
    commit;
    """
    code = require(sql(setup))
    if len(code) != 64 or any(c not in '0123456789abcdef' for c in code):
        raise RuntimeError('Expected a single valid server-generated code (value withheld).')
    barrier = threading.Barrier(2)
    def accept():
        barrier.wait(timeout=10)
        return sql(f"begin; {claims(WORKER)} select public.accept_team_invitation('{code}'); select pg_sleep(1); commit;")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(accept) for _ in range(2)]
        results = [future.result() for future in futures]
    if sorted(r.returncode for r in results) != [0, 3]:
        raise RuntimeError('Concurrent accepts must yield exactly one success and one SQL rejection.')
    counts = require(sql(f"select (select count(*) from public.team_members where user_id='{WORKER}'), (select count(*) from public.team_invitations where accepted_by='{WORKER}');"))
    if counts != '1|1':
        raise RuntimeError('Concurrent acceptance did not leave one membership and one consumed invite.')
    print('PASS: concurrent acceptance: one success, one rejection, one employee membership, one consumed invitation.')

if __name__ == '__main__':
    main()
