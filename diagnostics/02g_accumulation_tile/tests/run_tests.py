#!/usr/bin/env python3
"""Reuse the existing Linux resource supervisor, with a fixed task deadline."""
from datetime import datetime,timezone
import hashlib,importlib.util,json,sys,time,os
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
REPO=ROOT.parents[1]
path=REPO/'diagnostics/land_network_topology/synthetic_scale/run_validation.py'
spec=importlib.util.spec_from_file_location('supervisor',path)
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
base.HERE=ROOT;base.REPORT=ROOT/'results.json'
section=sys.argv[1] if len(sys.argv)>1 else 'all'
assert section in ('all','small','tiles','performance')
start=time.time()
RSCRIPT=os.environ.get("MM_RSCRIPT","Rscript")
r=json.loads(base.REPORT.read_text()) if base.REPORT.exists() else {'execution_s':0.,'runs':[],
 'started_utc':datetime.fromtimestamp(start,timezone.utc).isoformat(),'deadline_epoch':start+1200,
 'wall_budget_s':1200,'address_space_limit_mib':1536,'aggregate_rss_stop_mib':1792,
 'parent_commit':'f626ba465d8c044acb0ad981da18667fbfa98df6','research_plan_commit':'053df7c32d22391ccc1fb14d10d82e969bdb6bd3'}
r.setdefault('source_snapshots',[]).append({str(p.relative_to(REPO)):hashlib.sha256(p.read_bytes()).hexdigest()
 for p in ROOT.rglob('*') if p.suffix in ('.R','.py')})
out=[]
for name,file,n in [('small','test_accumulation.R',15),('tiles','test_tiles.R',27),('performance','performance.R',1000)]:
 if section not in ('all',name):continue
 x=base.run_one(r,[RSCRIPT,'--vanilla',str(HERE/file)],
  {'phase':'prototype','name':name,'n':n,'scenario':name,'cap':32},180)
 out.append(x)
 if x['status']!='PASS':
  r['last_completed_utc']=datetime.now(timezone.utc).isoformat();base.save(r);raise SystemExit(1)
if section=='all':
 perf=out[-1]
 r['runs'].append({'phase':'optional','name':'10000_cells','n':10000,'status':'NOT_RUN_RESOURCE_GATE',
  'reason':'BOUNDED_PROTOTYPE_1000_CELLS_AND_CONSERVATIVE_MEMORY_HEADROOM',
  'projected_rss_mib':15*max(perf['peak_rss_mib'],perf['peak_group_rss_mib'])})
 files=[REPO/'diagnostics/land_network_topology'/f for f in ['test_land_network_topology.R','test_land_network_topology_inventory.R',
  'test_one_low_network_window.R','test_boundary_receivers.R','../land_d8_continuity/test_land_d8_route.R',
  '../land_first_water/test_first_water_contact.R','../low_d8_scope/test_lake_1847_focus.R','../../tests/water_connected_route_diagnostics.R']]
 for p in files:
  out.append(base.run_one(r,[RSCRIPT,'--vanilla',str(p.resolve())],
   {'phase':'regression','name':p.stem,'scenario':'regression'},60))
 out.append(base.run_one(r,['python3','-B',str(path.parent/'test_supervisor.py')],
  {'phase':'regression','name':'test_supervisor','scenario':'regression'},10))
r['last_completed_utc']=datetime.now(timezone.utc).isoformat();base.save(r)
assert out and all(x['status']=='PASS' for x in out)
