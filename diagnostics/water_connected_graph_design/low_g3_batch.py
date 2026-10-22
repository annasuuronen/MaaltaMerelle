#!/usr/bin/env python3
"""LOW G3: grouped, read-only RANTA10/02C/02F spatial evidence, NOT routing."""
from __future__ import annotations

import argparse
from collections import Counter, deque
import csv
import ctypes as C
from pathlib import Path
import math
import sqlite3
import struct
import sys
from urllib.parse import quote

from low_geos_backend import Store, center, decode_gpkg_wkb, point_wkb

COMPONENT_TO_CELL = {108:10007129,109:10031127,235:15389414,236:15401414,
                     274:23211319,276:23355315,277:23373314}
EXPECTED_NEIGHBORS = {108:1,109:2,235:5,236:1,274:3,276:3,277:3}
TINY_LIMIT = 15_000_000
SYKE_XY = (209277.1, 6907673.6)


def require(ok, reason):
    if not ok:
        raise ValueError("STOP: " + reason)


def rows(path, mandatory):
    require(path.is_file() and not path.is_symlink(), "CSV_MISSING_OR_SYMLINK_"+path.name)
    require(0 < path.stat().st_size <= TINY_LIMIT, "CSV_SIZE_"+path.name)
    with path.open("r",newline="",encoding="utf-8-sig") as f:
        rd=csv.DictReader(f)
        require(rd.fieldnames and set(mandatory).issubset(rd.fieldnames),
                "CSV_SCHEMA_"+path.name)
        result=list(rd)
    require(len(result)<=200000, "CSV_ROWS_"+path.name)
    return result


def intid(row,key, allow_null=False):
    s=str(row[key]).strip()
    if allow_null and s in ("","NA","NaN","(null)"):
        return None
    try:
        a=float(s)
    except (ValueError,OverflowError):
        raise ValueError("STOP: NONNUMERIC_"+key) from None
    require(math.isfinite(a) and a.is_integer() and abs(a)<=2**53,
            "INVALID_INT_"+key)
    return int(a)


def cell_square_wkb(cell):
    x,y=center(cell)
    pts=((x-1.,y-1.),(x+1.,y-1.),(x+1.,y+1.),(x-1.,y+1.),(x-1.,y-1.))
    return b"\x01" + struct.pack("<III",3,1,5) + b"".join(struct.pack("<dd",*pt) for pt in pts)


def configure_geos(g):
    specs={
        "GEOSBoundary_r":(C.c_void_p,[C.c_void_p,C.c_void_p]),
        "GEOSGeomGetStartPoint_r":(C.c_void_p,[C.c_void_p,C.c_void_p]),
        "GEOSGeomGetEndPoint_r":(C.c_void_p,[C.c_void_p,C.c_void_p]),
        "GEOSGeomGetX_r":(C.c_int,[C.c_void_p,C.c_void_p,C.POINTER(C.c_double)]),
        "GEOSGeomGetY_r":(C.c_int,[C.c_void_p,C.c_void_p,C.POINTER(C.c_double)]),
    }
    for name,(ret,args) in specs.items():
        require(hasattr(g.lib,name),"GEOS_API_MISSING_"+name)
        fn=getattr(g.lib,name)
        fn.restype,fn.argtypes=ret,args


def created_geom(g, function, geom):
    result=getattr(g.lib,function)(g.ctx,geom)
    require(bool(result),"GEOS_OPERATION_FAILED_"+function)
    g.geom_handles.append(result)
    return result


def xy(g, point_geom):
    x,y=C.c_double(),C.c_double()
    require(g.lib.GEOSGeomGetX_r(g.ctx,point_geom,C.byref(x))==1 and
            g.lib.GEOSGeomGetY_r(g.ctx,point_geom,C.byref(y))==1,
            "GEOS_ENDPOINT_COORD")
    require(math.isfinite(x.value) and math.isfinite(y.value),"GEOS_NONFINITE_ENDPOINT")
    return x.value,y.value


def line_endpoints(g, geom):
    a=created_geom(g,"GEOSGeomGetStartPoint_r",geom)
    b=created_geom(g,"GEOSGeomGetEndPoint_r",geom)
    return xy(g,a),xy(g,b)


def load_lines(gpkg, g):
    path=Path(gpkg)
    require(path.is_file() and not path.is_symlink(), "GPKG_PATH_NOT_FILE")
    uri="file:"+quote(str(path.resolve()),safe="/")+"?mode=ro&immutable=1"
    con=sqlite3.connect(uri,uri=True,timeout=4)
    try:
        con.execute("PRAGMA query_only=ON")
        data=con.execute('SELECT fid,objectid,geom FROM "river_lines" ORDER BY fid LIMIT 31').fetchall()
    finally:
        con.close()
    require(len(data)==30,"RIVER_LINE_COUNT_CHANGED")
    seen=set()
    result=[]
    for fid,obj,blob in data:
        require(isinstance(fid,int) and fid not in seen, "BAD_FID")
        seen.add(fid)
        require(obj is not None and math.isfinite(float(obj)),"BAD_LINE_OBJECTID")
        geom=g.geom(decode_gpkg_wkb(blob))
        require(g.measure("valid",geom)==1,"INVALID_RIVER_LINE_GEOMETRY")
        result.append({"fid":fid,"objectid":str(obj),"geom":geom})
    return result


def shortest_line_chain(g, lines, source_geom, target_geom, threshold):
    """Geometric chain at threshold, not a D8 or hydrologic path."""
    sources=[i for i,l in enumerate(lines) if g.measure("distance",l["geom"],source_geom)<=threshold]
    targets={i for i,l in enumerate(lines) if g.measure("distance",l["geom"],target_geom)<=threshold}
    queue=deque(sources)
    pred={i:None for i in sources}
    while queue:
        i=queue.popleft()
        if i in targets:
            chain=[]
            while i is not None:
                chain.append(lines[i]["fid"])
                i=pred[i]
            return len(sources),len(targets),list(reversed(chain))
        for j,l in enumerate(lines):
            if j not in pred and g.measure("distance",lines[i]["geom"],l["geom"])<=threshold:
                pred[j]=i
                queue.append(j)
    return len(sources),len(targets),[]


def geometry(g, lines, lakes):
    a,b=lakes[1894],lakes[1892]
    print("G3_LINE_IDS: fid,objectid,distance_to_1894_m,distance_to_1892_m,start_x,start_y,end_x,end_y")
    rec=[]
    for line in lines:
        x,y=line_endpoints(g,line["geom"])
        da=g.measure("distance",line["geom"],a)
        db=g.measure("distance",line["geom"],b)
        rec.append((da+db,line["fid"],line["objectid"],da,db,x,y))
    for _,fid,obj,da,db,start,end in sorted(rec)[:12]:
        print(fid,obj,f"{da:.2f}",f"{db:.2f}",*map(lambda p:f"({p[0]:.1f},{p[1]:.1f})",(start,end)))
    print("G3_SINGLE_LINE_NEAR_BOTH_LAKES: threshold_m,count,fids")
    for tol in (0,1,2,5,10):
        fids=[item[1] for item in rec if item[3]<=tol and item[4]<=tol]
        print(tol,len(fids),",".join(map(str,sorted(fids))) or "NONE")
    print("G3_GEOMETRIC_LINE_CHAINS: tolerance_m,n_source_lines,n_target_lines,shortest_fid_chain")
    for tol in (0,1,2,5,10):
        ns,nt,chain=shortest_line_chain(g,lines,a,b,tol)
        print(tol,ns,nt,",".join(map(str,chain)) or "NONE")
    print("CAUTION: geometric distances and connections do NOT establish flow direction.")


def near_lines(g,lines):
    print("G3_NEAREST_LINES: component,terminal_cell,rank,line_fid,line_objectid,distance_m")
    for component,cell in COMPONENT_TO_CELL.items():
        point=g.geom(point_wkb(*center(cell)))
        near=sorted((g.measure("distance",point,line["geom"]),line["fid"],line["objectid"])
                    for line in lines)[:3]
        for rank,(d,fid,obj) in enumerate(near,1):
            print(component,cell,rank,fid,obj,f"{d:.2f}")


def neighbors(g,lines,lakes,baseline):
    data=rows(baseline/"02C_zero_pointer_water_neighbors.csv",
              ("component_id","source_cell","water_cell","water_class","lake_objectid"))
    selected=[]
    for row in data:
        comp=intid(row,"component_id")
        if comp not in COMPONENT_TO_CELL: continue
        src,water=intid(row,"source_cell"),intid(row,"water_cell")
        cls=intid(row,"water_class")
        lid=intid(row,"lake_objectid",allow_null=True)
        require(src==COMPONENT_TO_CELL[comp],"02C_SOURCE_MISMATCH")
        require(cls in (1,2,3),"BAD_WATER_CLASS")
        require(1<=water<=36_000_000,"WATER_CELL_OUT_OF_RANGE")
        x0,y0=center(src)
        x1,y1=center(water)
        require(max(abs(x1-x0),abs(y1-y0))==2,"NOT_ADJACENT_WATER_CELL")
        require((cls==1 and lid in lakes) or (cls!=1 and lid is None),
                "WATER_LAKE_ID_CLASS_MISMATCH")
        selected.append((comp,src,water,cls,lid))
    require(Counter(i[0] for i in selected)==Counter(EXPECTED_NEIGHBORS),
            "02C_NEIGHBOR_COUNT_CHANGED")
    print("G3_WATER_NEIGHBOR_FOOTPRINT: component,water_cell,raster_class,raster_lake,expected_vector_centroid_hit,expected_vector_2m_square_hit,nearest_expected_vector_m,other_type_square_hit")
    agg=Counter()
    for comp,src,water,cls,lid in sorted(selected):
        pt=g.geom(point_wkb(*center(water)))
        square=g.geom(cell_square_wkb(water))
        if cls==1:
            target=lakes[lid]
            other=[line["geom"] for line in lines]
        elif cls==3:
            target=min((line["geom"] for line in lines),key=lambda geom:g.measure("distance",pt,geom))
            other=list(lakes.values())
        else:
            # Original current seven-component observations have no class 2.
            raise ValueError("STOP: UNEXPECTED_RIVER_AREA_CLASS")
        centroid=g.measure("intersects",pt,target)
        footprint=g.measure("intersects",square,target)
        other_hit=int(any(g.measure("intersects",square,o) for o in other))
        d=g.measure("distance",pt,target)
        agg[(cls,centroid,footprint,other_hit)]+=1
        print(comp,water,cls,lid if lid is not None else "NA",centroid,footprint,f"{d:.2f}",other_hit)
    print("G3_FOOTPRINT_SUMMARY: class,center_hit,square_hit,other_water_type_square_hit,n")
    for key,n in sorted(agg.items()):
        print(*key,n)
    print("NOTE: square overlap may differ from terra rasterization precedence. No mask reclassification.")


def shoreline(g,lakes):
    lake=lakes[3181]
    boundary=created_geom(g,"GEOSBoundary_r",lake)
    pt=g.geom(point_wkb(*SYKE_XY))
    print("G3_SYKE_LAKE3181: point_id,point_inside_or_boundary,point_to_polygon_boundary_m")
    print(7025519,g.measure("intersects",pt,lake),f"{g.measure('distance',pt,boundary):.2f}")
    print("G3_COMPONENT_TO_3181_BOUNDARY: component,distance_m")
    for component in (108,109,235,236):
        cell=COMPONENT_TO_CELL[component]
        p=g.geom(point_wkb(*center(cell)))
        print(component,f"{g.measure('distance',p,boundary):.2f}")


def existing_routes(g,lines,lakes,baseline):
    data=rows(baseline/"02F_water_connected_route_evidence.csv",
              ("route_id","start_receiver_cell","origin_lake_objectid","terminal_cell",
               "terminal_lake_objectid","route_steps","route_status"))
    require(len(data)==101,"02F_TOTAL_ROUTE_COUNT_CHANGED")
    ids=[intid(r,"route_id") for r in data]
    require(len(set(ids))==len(ids),"DUPLICATE_02F_ROUTE_ID")
    hits=[r for r in data if intid(r,"origin_lake_objectid")==1894 and
          intid(r,"terminal_cell")==COMPONENT_TO_CELL[274]]
    require(len(hits)==6,"02F_1894_TO_274_ROUTE_COUNT_CHANGED")
    print("G3_02F_EXISTING_ROUTES: route_id,start_receiver_cell,terminal_cell,steps,status,terminal_lake_id,dist_start_to_1894_m,dist_start_to_1892_m,dist_start_to_nearest_line_m")
    for r in sorted(hits,key=lambda row:intid(row,"route_id")):
        start=intid(r,"start_receiver_cell")
        require(1<=start<=36_000_000,"02F_START_CELL_OUT_OF_RANGE")
        require(r["route_status"]=="D8_ZERO_INTERIOR","02F_STATUS_CHANGED")
        require(intid(r,"route_steps")>=0,"02F_INVALID_STEP")
        p=g.geom(point_wkb(*center(start)))
        dl=min(g.measure("distance",p,l["geom"]) for l in lines)
        print(intid(r,"route_id"),start,COMPONENT_TO_CELL[274],r["route_steps"],
              r["route_status"],intid(r,"terminal_lake_objectid",True) or "NA",
              f"{g.measure('distance',p,lakes[1894]):.2f}",
              f"{g.measure('distance',p,lakes[1892]):.2f}",f"{dl:.2f}")
    print("G3_02F_CONSTRAINT: six 02F route summaries, not complete per-cell D8 chains; no routing validation.")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--gpkg",type=Path,required=True)
    ap.add_argument("--baseline",type=Path,required=True)
    a=ap.parse_args()
    failures=[]
    print("=== TULOKSET ALKAVAT ===",flush=True)
    store=None
    try:
        store=Store(a.gpkg)
        g=store.geos
        configure_geos(g)
        lines=load_lines(a.gpkg,g)
        lakes={idx:geom for idx,_,geom in store.records["lakes"]}
        print("G3_SOURCE_GPKG=PASS lakes=24 river_areas=5 river_lines=30 SRS=3067")
        def step(label,fn):
            try:
                fn()
            except (ValueError,KeyError,OSError,sqlite3.Error) as e:
                failures.append(label)
                print("TEST_"+label+"=STOP: "+str(e)[:320],flush=True)
            else:
                print("TEST_"+label+"=PASS",flush=True)
        step("LAKE1894_1892_LINE_CONTINUITY",lambda:geometry(g,lines,lakes))
        step("SEVEN_TERMINALS_NEAREST_LINES",lambda:near_lines(g,lines))
        step("02C_2M_WATER_NEIGHBOR_FOOTPRINTS",lambda:neighbors(g,lines,lakes,a.baseline))
        step("SYKE_POINT3181_SHORELINE_DISTANCE",lambda:shoreline(g,lakes))
        step("02F_EXISTING_SIX_ROUTE_SUMMARIES",lambda:existing_routes(g,lines,lakes,a.baseline))
    except (ValueError,OSError,sqlite3.Error) as e:
        failures.append("G3_PREFLIGHT")
        print("TEST_G3_PREFLIGHT=STOP: "+str(e)[:320],flush=True)
    finally:
        if store is not None:store.close()
    print("SCIENTIFIC_LOCKS: NATIONAL=LOCKED MODERATE=REVIEW_REQUIRED hydrological_validation=NOT_ASSESSED channel_interpretation=NOT_ASSESSED")
    print("BATCH_STATUS="+("PASS" if not failures else "PARTIAL")+" FAILED_STAGES="+(",".join(failures) if failures else "NONE"))
    print("=== TULOKSET LOPPUVAT ===",flush=True)
    return 0 if not failures else 1

if __name__=="__main__":
    sys.exit(main())
