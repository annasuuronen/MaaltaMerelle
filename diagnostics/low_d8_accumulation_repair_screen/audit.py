#!/usr/bin/env python3
"""Deterministic equal-area LOW D8 screen, NOT an estimate of repairs needed."""
import argparse
import csv
import json
import math
import random
import sys
import unittest
from collections import Counter
SIZE = 6000
STRATA = 16
N = 256
SEED = 20261022
D8 = {1:(-1,1),2:(0,1),4:(1,1),8:(1,0),16:(1,-1),32:(0,-1),64:(-1,-1),128:(-1,0)}

def idof(row, col):
    if not (1 <= row <= SIZE and 1 <= col <= SIZE):
        raise ValueError("CELL_OUT_OF_GRID")
    return (row-1)*SIZE+col

def cells_design():
    rng = random.Random(SEED)
    centers = []
    cells = set()
    side = SIZE//STRATA
    for br in range(STRATA):
        for bc in range(STRATA):
            row = br*side + 1 + rng.randrange(side)
            col = bc*side + 1 + rng.randrange(side)
            centers.append((row,col,idof(row,col)))
            for dr in (-1,0,1):
                for dc in (-1,0,1):
                    if 1 <= row+dr <= SIZE and 1 <= col+dc <= SIZE:
                        cells.add(idof(row+dr,col+dc))
    assert len(centers)==N and len({x[2] for x in centers})==N
    assert len(cells)<=N*9
    return centers,sorted(cells)

def finite(x):
    return math.isfinite(x)

def class_for(v):
    if math.isnan(v): return "LAND"
    if not finite(v): return "UNCLEAR"
    if v in (1,2,3): return "WATER"
    return "UNCLEAR"

def wilson(k,n):
    if not n: return None
    z = 1.959963984540054
    p = k/n
    den = 1+z*z/n
    a = (p+z*z/(2*n))/den
    h = z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/den
    return (max(0,a-h),min(1,a+h))

def row_classification(row,col,samples,tol=1e-6):
    p,z,w = samples[idof(row,col)]
    if not finite(z): return "SOURCE_NODATA",False
    kind = class_for(w)
    if kind=="WATER": return "SOURCE_WATER",False
    if kind=="UNCLEAR": return "SOURCE_UNCLEAR_CLASS",False
    if not finite(p): return "POINTER_MISSING",True
    if p==0: return "POINTER_ZERO",True
    if p not in D8: return "POINTER_INVALID",True
    dr,dc = D8[int(p)]
    rr,cc = row+dr,col+dc
    if not (1<=rr<=SIZE and 1<=cc<=SIZE): return "OFF_GRID_EDGE",True
    dst = samples.get(idof(rr,cc))
    if dst is None: raise ValueError("MISSING_EXPECTED_NEIGHBOUR")
    _,zt,wt = dst
    if class_for(wt)=="WATER": return "WATER_RECEIVER_CANDIDATE",True
    if class_for(wt)=="UNCLEAR": return "TARGET_UNCLEAR_CLASS",True
    if not finite(zt): return "TARGET_NODATA",True
    d=zt-z
    if d>tol: return "UPHILL_ROUTING_SURFACE",True
    if d>=-tol: return "NEAR_FLAT",True
    return "DOWNHILL_ROUTING_SURFACE",True

def result(centers,samples):
    counts=Counter()
    eligible=0
    for r,c,_ in centers:
        kind,land=row_classification(r,c,samples)
        counts[kind]+=1
        eligible+=int(land)
    if sum(counts.values())!=N or eligible==0: raise ValueError("INVALID_SCREEN_COUNTS")
    flags = ("POINTER_MISSING","POINTER_ZERO","POINTER_INVALID",
             "UPHILL_ROUTING_SURFACE","TARGET_NODATA","TARGET_UNCLEAR_CLASS")
    k=sum(counts[x] for x in flags)
    return {"area":"LOW E200000_N6900000",
            "n_strata":N,"n_centres":N,"n_eligible_land":eligible,
            "categories":dict(sorted(counts.items())),
            "land_screen_flags":k,
            "land_screen_fraction":round(k/eligible,6),
            "approx_wilson_95_land_screen_fraction":[round(v,6) for v in wilson(k,eligible)],
            "flag_definition":list(flags),
            "hydrological_corrections_needed":"NOT_ESTIMABLE_FROM_SAMPLE",
            "flow_accumulation":"NOT_COMPUTED_IN_BASELINE_PIPELINE",
            "hydrological_validation":"NOT_ASSESSED",
            "channel_interpretation":"NOT_ASSESSED",
            "MODERATE":"REVIEW_REQUIRED","NATIONAL":"LOCKED",
            "warning":"screen flags are not verified D8 errors; Wilson interval approximate; no national extrapolation"}

def make(centers_file,cells_file):
    centers,cells=cells_design()
    with open(centers_file,"w",newline="") as f:
        w=csv.writer(f);w.writerow(("row","col","cell_id"));w.writerows(centers)
    with open(cells_file,"w",newline="") as f:
        w=csv.writer(f);w.writerow(("cell_id",));w.writerows((x,) for x in cells)
    return len(cells)

def rows(path):
    with open(path,newline="") as f:
        return list(csv.DictReader(f))

def analyse(centers_file,raw_file):
    cs=rows(centers_file)
    expected,allowed=cells_design()
    if len(cs)!=N: raise ValueError("CENTER_COUNT_MISMATCH")
    centers=[]
    for row,truth in zip(cs,expected):
        observed=tuple(int(row[x]) for x in ("row","col","cell_id"))
        if observed!=truth: raise ValueError("CENTERS_OR_ORDER_CHANGED")
        centers.append(observed)
    data=rows(raw_file)
    if len(data)!=len(allowed): raise ValueError("RASTER_SAMPLE_SIZE_MISMATCH")
    samples={}
    for row,expected_id in zip(data,allowed):
        idx=int(row["cell_id"])
        if idx!=expected_id or idx in samples: raise ValueError("RASTER_CELL_ORDER_CHANGED")
        samples[idx]=(float(row["pointer"]),float(row["z"]),float(row["water_class"]))
    return result(centers,samples)

class Tests(unittest.TestCase):
    def test_sample_design(self):
        a,b=cells_design()
        self.assertEqual(len(a),256)
        self.assertEqual(len(set(b)),len(b))
        self.assertLessEqual(len(b),2304)
        self.assertEqual(a,cells_design()[0])
    def test_index_and_directions(self):
        self.assertEqual(idof(1,1),1)
        self.assertEqual(idof(6000,6000),36000000)
        self.assertEqual(len(set(D8.values())),8)
        with self.assertRaises(ValueError): idof(0,1)
    def test_direction_synthetic(self):
        r,c=200,200
        for p,(dr,dc) in D8.items():
            sample={idof(r,c):(p,100,float("nan")),
                    idof(r+dr,c+dc):(0,99,float("nan"))}
            self.assertEqual(row_classification(r,c,sample)[0],"DOWNHILL_ROUTING_SURFACE")
        for p,status in [(0,"POINTER_ZERO"),(3,"POINTER_INVALID"),
                         (float("nan"),"POINTER_MISSING")]:
            self.assertEqual(row_classification(r,c,{idof(r,c):(p,100,float("nan"))})[0],status)
    def test_uphill_flat_nodata_water(self):
        r,c=200,200
        for z,w,status in [(101,float("nan"),"UPHILL_ROUTING_SURFACE"),
                           (100,float("nan"),"NEAR_FLAT"),
                           (float("nan"),float("nan"),"TARGET_NODATA"),
                           (2,2,"WATER_RECEIVER_CANDIDATE"),
                           (80,9,"TARGET_UNCLEAR_CLASS")]:
            data={idof(r,c):(2,100,float("nan")),idof(r,c+1):(2,z,w)}
            self.assertEqual(row_classification(r,c,data)[0],status)
    def test_source_cases(self):
        r,c=222,333
        for z,w,status in [(float("nan"),float("nan"),"SOURCE_NODATA"),
                           (10,1,"SOURCE_WATER"),(10,4,"SOURCE_UNCLEAR_CLASS")]:
            self.assertEqual(row_classification(r,c,{idof(r,c):(2,z,w)})[0],status)
    def test_wilson(self):
        self.assertEqual(wilson(0,0),None)
        self.assertEqual(wilson(0,256)[0],0)
        self.assertLess(wilson(0,256)[1],0.02)
        self.assertLess(wilson(256,256)[0],1)

def main():
    p=argparse.ArgumentParser()
    s=p.add_subparsers(dest="mode",required=True)
    a=s.add_parser("make");a.add_argument("--centers",required=True);a.add_argument("--cells",required=True)
    a=s.add_parser("analyse");a.add_argument("--centers",required=True);a.add_argument("--raw",required=True)
    s.add_parser("selftest")
    x=p.parse_args()
    if x.mode=="selftest":
        suite=unittest.defaultTestLoader.loadTestsFromTestCase(Tests)
        z=unittest.TextTestRunner(verbosity=1).run(suite)
        print(f"TESTS={z.testsRun} PASS={z.testsRun-len(z.failures)-len(z.errors)} FAIL={len(z.failures)+len(z.errors)}")
        return 0 if z.wasSuccessful() and z.testsRun==6 else 1
    if x.mode=="make":
        print(f"CENTERS={N} UNIQUE_NEIGHBORHOOD_CELLS={make(x.centers,x.cells)}",file=sys.stderr)
        return 0
    answer=analyse(x.centers,x.raw)
    print("=== TULOKSET ALKAVAT ===")
    print(json.dumps(answer,ensure_ascii=False,indent=2,sort_keys=True))
    return 0

if __name__=="__main__":
    try: sys.exit(main())
    except Exception as e:
        print(f"STOP: {type(e).__name__}: {e}",file=sys.stderr)
        sys.exit(1)
