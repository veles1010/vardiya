"""Leave/shift races: real independent sessions, disposable CI container only."""
import concurrent.futures
import threading
from test_invite_concurrency import sql, require, claims
O='70000000-0000-0000-0000-000000000001'
W='70000000-0000-0000-0000-000000000002'

def team(n): return f'70000000-0000-0000-0000-{100+n:012d}'
def fixture(n, approved=False, draft=False):
    t=team(n)
    require(sql(f"insert into public.teams(id,name,created_by) values('{t}','Leave race','{O}'); insert into public.team_members values('{t}','{O}','owner'),('{t}','{W}','employee');"))
    v=0
    if draft:
        require(sql(f"begin; {claims(O)} {save(t,v)}; commit;"));v+=1
    rid=require(sql(f"begin; {claims(W)} select public.create_team_leave('{t}',{v},'2026-10-26','2026-10-26','');commit;"));v+=1
    if approved:
        require(sql(f"begin; {claims(O)} {act(t,v,rid)};commit;"));v+=1
    return t,rid,v

def save(t,v): return f"select public.save_team_shift('{t}',{v},null,'{W}','2026-10-25 22:00','2026-10-26 06:00',0,'Night','')"
def act(t,v,rid,action='approve',revision=0): return f"select public.act_on_team_leave('{t}',{v},'{rid}',{revision},'{action}','Race reason')"
def race(a,b,person=O):
    barrier=threading.Barrier(2)
    def run(q):
        barrier.wait(timeout=10)
        return sql(f"begin; {claims(person)} {q};select pg_sleep(1);commit;")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(run,q) for q in [a,b]]
        results=[f.result() for f in futures]
    if sorted(r.returncode for r in results)!=[0,3]: raise RuntimeError('Expected one commit and one SQL rejection in leave race.')
    rejected=next(r for r in results if r.returncode)
    if not any(s in rejected.stderr for s in ['Plan changed; refresh','Request changed; refresh','Shift overlaps approved leave','Leave conflicts with draft or published shifts']):
        raise RuntimeError('Leave race failed for an unexpected infrastructure or SQL reason.')

def consistent(t):
    count=require(sql(f"select count(*) from public.team_leave_requests l join (select * from public.team_shift_drafts union all select * from public.team_shift_published) s on s.team_id=l.team_id and s.user_id=l.user_id where l.team_id='{t}' and l.status='approved' and s.starts_at<(l.ends_on+1)::timestamp and s.ends_at>l.starts_on::timestamp;"))
    if count!='0': raise RuntimeError('Approved leave and shifts overlap after a race.')

def main():
    require(sql(f"insert into auth.users(id,email) values('{O}','leave-race-owner@example.invalid'),('{W}','leave-race-worker@example.invalid');"))
    t,r,v=fixture(1);race(act(t,v,r),save(t,v));consistent(t)
    t,r,v=fixture(2,draft=True);race(act(t,v,r),f"select public.publish_team_plan('{t}',{v})");consistent(t)
    t,r,v=fixture(3,approved=True);race(act(t,v,r,'cancel',1),save(t,v));consistent(t)
    t,r,v=fixture(4);race(act(t,v,r),act(t,v,r));consistent(t)
    if require(sql(f"select count(*) from public.team_leave_events where request_id='{r}' and status='approved'"))!='1': raise RuntimeError('Duplicate approval event.')
    # Two employees requests for the same interval from one version.
    t=team(5);require(sql(f"insert into public.teams(id,name,created_by) values('{t}','Create race','{O}'); insert into public.team_members values('{t}','{O}','owner'),('{t}','{W}','employee');"))
    q=f"select public.create_team_leave('{t}',0,'2026-11-01','2026-11-02','')"
    race(q,q,person=W)
    if require(sql(f"select count(*) from public.team_leave_requests where team_id='{t}'"))!='1': raise RuntimeError('Duplicate active requests.')
    print('PASS: leave approval/save, approval/publication, cancellation/save, double decision and overlapping requests: consistent final state, no duplicate decisions.')

if __name__=='__main__': main()
