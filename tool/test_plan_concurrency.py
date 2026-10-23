"""Real competing sessions in the disposable CI PostgreSQL only."""
import concurrent.futures
import threading
from test_invite_concurrency import sql, require, claims
OWNER = '50000000-0000-0000-0000-000000000001'
TEAM = '50000000-0000-0000-0000-000000000010'

def race(a, b):
    barrier = threading.Barrier(2)
    def run(query):
        barrier.wait(timeout=10)
        return sql(f"begin; {claims(OWNER)} {query}; select pg_sleep(1); commit;")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(run, q) for q in [a, b]]
        results = [f.result() for f in futures]
    if sorted(r.returncode for r in results) != [0, 3]:
        raise RuntimeError('Expected exactly one commit and one stale-version rejection.')
    failed = next(r for r in results if r.returncode)
    if 'Plan changed; refresh' not in failed.stderr:
        raise RuntimeError('Competing operation failed for a reason other than version control.')

def save(v, start='22:00', end='06:00'):
    return f"select public.save_team_shift('{TEAM}',{v},null,'{OWNER}','2026-10-25 {start}','2026-10-26 {end}',60,'Night','')"

def main():
    require(sql(f"insert into auth.users(id,email) values('{OWNER}','plan-race@example.invalid'); insert into public.teams(id,name,created_by) values('{TEAM}','Plan race','{OWNER}'); insert into public.team_members values('{TEAM}','{OWNER}','owner');"))
    race(save(0), save(0, '23:00', '07:00'))
    if require(sql(f"select count(*) from public.team_shift_drafts where team_id='{TEAM}'")) != '1':
        raise RuntimeError('Concurrent overlaps left multiple drafts.')
    # Publication competes with a non-overlapping edit, both from the same snapshot.
    race(f"select public.publish_team_plan('{TEAM}',1)", f"select public.save_team_shift('{TEAM}',1,null,'{OWNER}','2026-10-27 08:00','2026-10-27 16:00',30,'Day','')")
    if require(sql(f"select version from public.team_plans where team_id='{TEAM}'")) != '2':
        raise RuntimeError('Competing publish/edit silently overwrote a change.')
    # Simultaneous publications also cannot both succeed from the old version.
    race(f"select public.publish_team_plan('{TEAM}',2)", f"select public.publish_team_plan('{TEAM}',2)")
    if require(sql(f"select version=3 and published_version=3 and (select count(*) from public.team_shift_published where team_id='{TEAM}')=(select count(*) from public.team_shift_drafts where team_id='{TEAM}') from public.team_plans where team_id='{TEAM}'")) != 't':
        raise RuntimeError('Publication metadata and snapshot are inconsistent.')
    print('PASS: concurrent overlapping edits, edit/publication and two publications: one commit and one stale rejection each; complete snapshot.')

if __name__ == '__main__':
    main()
