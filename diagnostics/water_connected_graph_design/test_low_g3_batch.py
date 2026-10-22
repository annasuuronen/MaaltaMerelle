"""Synthetic and fail-closed tests for one-pass LOW G3 geometry audit."""
import contextlib
import io
from pathlib import Path
import sqlite3
import struct
import sys
import tempfile
import unittest
from unittest import mock

import low_geos_backend as b
import low_g3_batch as g3


def polygon(x,y,w=20,h=20):
    pts=((x,y),(x+w,y),(x+w,y+h),(x,y+h),(x,y))
    return b"\x01"+struct.pack("<III",3,1,5)+b"".join(struct.pack("<dd",*v) for v in pts)


def line(x1,y1,x2,y2):
    return b"\x01"+struct.pack("<II",2,2)+struct.pack("<dddd",x1,y1,x2,y2)


def blob(wkb):
    return b"GP\x00\x01"+struct.pack("<i",3067)+wkb


def make_fixture(base):
    gpkg=base/"ranta.gpkg"
    con=sqlite3.connect(gpkg)
    con.execute("CREATE TABLE gpkg_geometry_columns(table_name TEXT,srs_id INTEGER,geometry_type_name TEXT)")
    for k,n in b.SIZES.items():
        con.execute("INSERT INTO gpkg_geometry_columns VALUES (?,3067,?)",
                    (k,"LINESTRING" if k=="river_lines" else "POLYGON"))
        if k=="lakes":
            con.execute("CREATE TABLE lakes(fid INTEGER PRIMARY KEY,objectid REAL,korkeus_m REAL,geom BLOB)")
            values=[
                (1892,0.37,polygon(205630,6903245)),
                (1894,0.44,polygon(205640,6903200)),
                (3181,0.92,polygon(209240,6907640,60,45))
            ]
            values += [(90000+i,None,polygon(201000+i*30,6901000)) for i in range(21)]
            for i,(obj,height,wkb) in enumerate(values):
                con.execute("INSERT INTO lakes VALUES(?,?,?,?)",(i+1,obj,height,blob(wkb)))
        elif k=="river_areas":
            con.execute("CREATE TABLE river_areas(fid INTEGER PRIMARY KEY,objectid REAL,geom BLOB)")
            for i in range(n):
                con.execute("INSERT INTO river_areas VALUES (?,?,?)",
                            (i+1,200+i,blob(polygon(209250+i*50,6907600))))
        else:
            con.execute("CREATE TABLE river_lines(fid INTEGER PRIMARY KEY,objectid REAL,geom BLOB)")
            line0=line(205650,6903220,205650,6903245)
            for i in range(n):
                wkb=line0 if i==0 else line(209245+i*100,6907650,209247+i*100,6907652)
                con.execute("INSERT INTO river_lines VALUES(?,?,?)",(i+1,300+i,blob(wkb)))
    con.commit();con.close()
    qa=base/"02C_zero_pointer_water_neighbors.csv"
    with qa.open("w") as f:
        f.write("component_id,source_cell,water_cell,water_class,lake_objectid\n")
        for comp,c in g3.COMPONENT_TO_CELL.items():
            lake=3181 if comp in (108,109,235,236) else (1892 if comp==274 else 1894)
            for j in range(g3.EXPECTED_NEIGHBORS[comp]):
                water=c+[1,-1,6000,-6000,6001][j]
                cl=3 if comp==235 and j==4 else 1
                f.write(f"{comp},{c},{water},{cl},{'' if cl==3 else lake}\n")
    with (base/"02F_water_connected_route_evidence.csv").open("w") as f:
        f.write("route_id,start_receiver_cell,origin_lake_objectid,terminal_cell,terminal_lake_objectid,route_steps,route_status\n")
        for i in range(101):
            match=i<6
            f.write(f"{i+1},{23355315+i},{1894 if match else 1892},{23211319 if match else 10007129},,3,D8_ZERO_INTERIOR\n")
    return gpkg


class G3Tests(unittest.TestCase):
    def test_neighbor_set_7_components_18_pairs(self):
        self.assertEqual(len(g3.COMPONENT_TO_CELL),7)
        self.assertEqual(sum(g3.EXPECTED_NEIGHBORS.values()),18)

    def test_cell_footprint_is_2m_square(self):
        w=g3.cell_square_wkb(23211319)
        self.assertEqual(w[0],1)
        self.assertEqual(struct.unpack_from("<III",w,1),(3,1,5))
        coords=[struct.unpack_from("<dd",w,13+16*i) for i in range(5)]
        self.assertEqual(coords[0],coords[-1])
        self.assertEqual(max(x for x,y in coords)-min(x for x,y in coords),2)
        self.assertEqual(max(y for x,y in coords)-min(y for x,y in coords),2)

    def test_nonfinite_integer_rejected(self):
        for wrong in ("","nan","inf","2.5"):
            with self.assertRaises(ValueError):
                g3.intid({"id":wrong},"id")

    def test_null_integer_optional(self):
        self.assertIsNone(g3.intid({"id":""},"id",True))
        self.assertEqual(g3.intid({"id":"1892.0"},"id"),1892)

    def test_missing_baseline_file_stops(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError,"CSV_MISSING"):
                g3.rows(Path(d)/"not_here.csv",["id"])

    def test_line_endpoint_xy_native_geos(self):
        native=b.Geos()
        try:
            g3.configure_geos(native)
            geom=native.geom(line(1,2,7,8))
            self.assertEqual(g3.line_endpoints(native,geom),((1.,2.),(7.,8.)))
        finally:
            native.close()

    def test_polygon_shoreline_boundary_distance_native(self):
        native=b.Geos()
        try:
            g3.configure_geos(native)
            poly=native.geom(polygon(0,0,20,20))
            boundary=g3.created_geom(native,"GEOSBoundary_r",poly)
            pt=native.geom(b.point_wkb(10,10))
            self.assertAlmostEqual(native.measure("distance",pt,boundary),10)
            self.assertEqual(native.measure("intersects",pt,poly),1)
        finally:
            native.close()

    def test_geometric_line_chain_threshold(self):
        native=b.Geos()
        try:
            la=native.geom(polygon(0,0))
            lb=native.geom(polygon(30,0))
            lines=[{"fid":1,"geom":native.geom(line(20,10,25,10))},
                   {"fid":2,"geom":native.geom(line(25,10,30,10))}]
            ns,nt,p=g3.shortest_line_chain(native,lines,la,lb,0)
            self.assertEqual((ns,nt,p),(1,1,[1,2]))
            lines[1]["geom"]=native.geom(line(27,10,30,10))
            self.assertEqual(g3.shortest_line_chain(native,lines,la,lb,0)[2],[])
            self.assertEqual(g3.shortest_line_chain(native,lines,la,lb,2)[2],[1,2])
        finally:
            native.close()

    def test_full_synthetic_gpkg_covers_five_stages(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)
            gpkg=make_fixture(path)
            with mock.patch.object(sys,"argv",["g3","--gpkg",str(gpkg),"--baseline",str(path)]):
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    result=g3.main()
            s=out.getvalue()
            self.assertEqual(result,0,s)
            for label in ("LAKE1894_1892_LINE_CONTINUITY","SEVEN_TERMINALS_NEAREST_LINES",
                          "02C_2M_WATER_NEIGHBOR_FOOTPRINTS","SYKE_POINT3181_SHORELINE_DISTANCE",
                          "02F_EXISTING_SIX_ROUTE_SUMMARIES"):
                self.assertIn("TEST_"+label+"=PASS",s)
            self.assertIn("G3_GEOMETRIC_LINE_CHAINS",s)
            self.assertIn("G3_FOOTPRINT_SUMMARY",s)
            self.assertIn("G3_02F_EXISTING_ROUTES",s)
            self.assertIn("BATCH_STATUS=PASS",s)

    def test_altered_02f_count_stops_but_other_stages_survive(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d);gpkg=make_fixture(path)
            f=path/"02F_water_connected_route_evidence.csv"
            lines=f.read_text().splitlines()
            f.write_text("\n".join(lines[:-1])+"\n")
            with mock.patch.object(sys,"argv",["g3","--gpkg",str(gpkg),"--baseline",str(path)]):
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    result=g3.main()
            s=out.getvalue()
            self.assertEqual(result,1)
            self.assertIn("TEST_02F_EXISTING_SIX_ROUTE_SUMMARIES=STOP",s)
            self.assertIn("TEST_LAKE1894_1892_LINE_CONTINUITY=PASS",s)
            self.assertIn("BATCH_STATUS=PARTIAL",s)

    def test_altered_02c_class_stops_without_modifying_input(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d);gpkg=make_fixture(path)
            f=path/"02C_zero_pointer_water_neighbors.csv"
            source=f.read_text()
            f.write_text(source.replace(",1,3181\n",",9,3181\n",1))
            with mock.patch.object(sys,"argv",["g3","--gpkg",str(gpkg),"--baseline",str(path)]):
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    result=g3.main()
            self.assertEqual(result,1)
            self.assertIn("02C_2M_WATER_NEIGHBOR_FOOTPRINTS=STOP",out.getvalue())
            self.assertEqual(f.read_text(),source.replace(",1,3181\n",",9,3181\n",1))


if __name__=="__main__":
    unittest.main()
