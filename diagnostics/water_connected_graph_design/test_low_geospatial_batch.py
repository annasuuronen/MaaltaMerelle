import contextlib
import io
from pathlib import Path
import sqlite3
import struct
import low_geos_backend as b
import tempfile
import unittest
from unittest import mock
import low_geospatial_batch as a


class LowGeoBatchTest(unittest.TestCase):
    def test_all_seven_centers(self):
        points = {
            10007129: (209257, 6907665), 10031127: (209253, 6907657),
            15389414: (209827, 6905871), 15401414: (209827, 6905867),
            23211319: (205637, 6903263), 23355315: (205629, 6903215),
            23373314: (205627, 6903209),
        }
        self.assertEqual({c: a.center(c) for c in a.CELLS}, points)

    def test_bounds(self):
        for bad in (0, -1, 6000*6000+1):
            with self.assertRaisesRegex(ValueError, "CELL_ID_OUT_OF_RANGE"):
                a.center(bad)

    def test_sql_grid_cte(self):
        s = a.grid_cte()
        self.assertIn("(10007129,209257,6907665)", s)
        self.assertIn("(23211319,205637,6903263)", s)
        self.assertEqual(s.count("),("), 6)
        self.assertNotIn("((", s)

    def test_parse_features(self):
        raw = "Layer name: SELECT\nOGRFeature(SELECT):0\n  lake_id (Integer) = 1892\n  distance_m (Real) = 2.56\nOGRFeature(SELECT):1\n  lake_id (Integer) = 3181\n"
        self.assertEqual(a.parse_features(raw), [{"lake_id":"1892","distance_m":"2.56"},{"lake_id":"3181"}])

    def test_parse_empty(self):
        self.assertEqual(a.parse_features("Layer name: SELECT\n"), [])

    def test_parse_nonnumeric_rejected(self):
        for row in ({"x":"(null)"}, {"x":"NaN"}, {"x":"abc"}):
            with self.assertRaises(ValueError):
                a.finite_number(row,"x")

    def test_read_only_gpkg_qa(self):
        with tempfile.TemporaryDirectory() as t:
            base = Path(t)
            gpkg = base / 'fixture.gpkg'
            con = sqlite3.connect(gpkg)
            con.execute('CREATE TABLE gpkg_geometry_columns (table_name TEXT, srs_id INTEGER)')
            for name,num in [('lakes',24),('river_areas',5),('river_lines',30)]:
                con.execute('INSERT INTO gpkg_geometry_columns VALUES (?,3067)',(name,))
                con.execute(f'CREATE TABLE {name}(id INTEGER)')
                con.executemany(f'INSERT INTO {name} VALUES (?)', [(i,) for i in range(num)])
            con.commit(); con.close()
            (base / a.ZERO_NEIGHBOR_FILE).write_text('component_id,source_cell,water_cell,water_class,lake_objectid\n')
            (base / a.COMPONENT_FILE).write_text('component_id,connector_status,water_signature,target_lake_objectid,n_zero_cells,lake_objectids\n')
            with mock.patch.object(a.subprocess,'run',return_value=mock.Mock(returncode=0)):
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    a.expect_files(gpkg,base)
            self.assertIn("'lakes': 24",out.getvalue())
            # A misleading full national result should be explicitly rejected.
            con=sqlite3.connect(gpkg); con.execute('DELETE FROM lakes WHERE id=23');con.commit();con.close()
            with mock.patch.object(a.subprocess,'run',return_value=mock.Mock(returncode=0)):
                with self.assertRaisesRegex(ValueError,"LAYER_COUNTS_CHANGED"):
                    a.expect_files(gpkg,base)

    def test_refuse_symlink(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); g=p/'gpkg';g.write_bytes(b'test');z=p/a.ZERO_NEIGHBOR_FILE
            z.symlink_to(g)
            with self.assertRaisesRegex(ValueError,'MISSING_OR_SYMLINK_FILE'):
                a.expect_files(g,p)

    def test_geometry_backend_uses_geos_not_spatial_sql(self):
        with mock.patch.object(b, "query", return_value=[{"lake_id": "1892"}]) as q:
            rows = a.ogr(Path("fixture.gpkg"), "SELECT INVALID_SPATIAL_SQL()", 1, "LAKE_INFO")
        self.assertEqual(rows, [{"lake_id": "1892"}])
        q.assert_called_once_with(Path("fixture.gpkg"), "LAKE_INFO")

    def test_geometry_backend_row_count_fail_closed(self):
        with mock.patch.object(b, "query", return_value=[]):
            with self.assertRaisesRegex(ValueError, "GEOS_ROW_COUNT"):
                a.ogr(Path("fixture.gpkg"), "SELECT 1", 1, "LAKE_INFO")

    def test_decode_gpkg_wkb_and_srs_guard(self):
        point = b.point_wkb(100.0, 200.0)
        header = b"GP" + bytes([0,1]) + struct.pack("<i", 3067)
        self.assertEqual(b.decode_gpkg_wkb(header + point), point)
        with self.assertRaisesRegex(ValueError, "NOT_3067"):
            b.decode_gpkg_wkb(header[:4] + struct.pack("<i", 4326) + point)
        with self.assertRaisesRegex(ValueError, "GPKG_MAGIC_VERSION"):
            b.decode_gpkg_wkb(b"GX" + header[2:] + point)

    def test_geos_native_metric_and_topology(self):
        g = b.Geos()
        try:
            # 10x10 m square, point at center, point 5m outside right edge
            xy = [(0.,0.),(10.,0.),(10.,10.),(0.,10.),(0.,0.)]
            wkb = b"\x01" + struct.pack("<III", 3, 1, len(xy))
            wkb += b"".join(struct.pack("<dd", *p) for p in xy)
            poly = g.geom(wkb)
            inside = g.geom(b.point_wkb(5,5))
            outside = g.geom(b.point_wkb(15,5))
            self.assertEqual(g.measure("valid", poly), 1)
            self.assertAlmostEqual(g.measure("area", poly), 100)
            self.assertEqual(g.measure("intersects", poly, inside), 1)
            self.assertEqual(g.measure("intersects", poly, outside), 0)
            self.assertAlmostEqual(g.measure("distance", poly, outside), 5)
        finally:
            g.close()

    def test_missing_geos_native_fails_closed(self):
        with mock.patch.object(b, "find_library", return_value=None), mock.patch.object(b.C, "CDLL", side_effect=OSError("unavailable")):
            with self.assertRaisesRegex(ValueError, "GEOS_C_NOT_AVAILABLE"):
                b.Geos()

    def test_neighbor_and_component_classes(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            with (p/a.COMPONENT_FILE).open('w') as f:
                f.write('component_id,connector_status,water_signature,target_lake_objectid,n_zero_cells,lake_objectids,terminal_minus_water_m\n')
                for c in sorted({n for n,o in a.CELLS.values()}):
                    f.write(f'{c},{"INTERIOR_REVIEW" if c==235 else "SAFE_LAKE_CONNECTOR"},{"MIXED" if c==235 else "LAKE_ONLY"},{"" if c==235 else "3181"},1,3181,-0.1\n')
            with (p/a.ZERO_NEIGHBOR_FILE).open('w') as f:
                f.write('component_id,source_cell,water_cell,water_class,lake_objectid\n')
                for c in sorted({n for n,o in a.CELLS.values()}):
                    f.write(f'{c},1,{c},1,3181\n')
                f.write('235,1,99999,2,\n')
            with contextlib.redirect_stdout(io.StringIO()) as out:
                a.csv_diagnostic(p)
            s=out.getvalue()
            self.assertIn('235 INTERIOR_REVIEW',s)
            self.assertIn('235 2 NA 1 1',s)

    def test_all_stages_report_and_fail_closed(self):
        def fake_ogr(gpkg, statement, expected_rows, label):
            if label=="LAKE_INFO":
                return [{"lake_id":str(i),"lake_height_m":"12.5","area_m2":"1000","geom_valid":"1"} for i in a.LAKES]
            if label=="LAKE_PAIR":
                return [{"distance_m":"3.0","touches":"0","intersects":"0"}]
            if label=="CELL_LAKE":
                return [{"cell":str(c),"lake_id":str(l),"distance_m":"1.0","inside":"0"} for c in sorted(a.CELLS) for l in a.LAKES]
            if label in ("river_areas","river_lines"):
                return [{"cell":str(c),"min_distance_m":"2.0"} for c in sorted(a.CELLS)]
            if label=="SYKE_POINT_LAKE":
                return [{"lake_id":str(i),"distance_m":"3.0","intersects":"0"} for i in a.LAKES]
            raise AssertionError(label)
        with contextlib.redirect_stdout(io.StringIO()) as stdout:
            with mock.patch.object(a,"expect_files"), mock.patch.object(a,"csv_diagnostic"), mock.patch.object(a,"ogr",side_effect=fake_ogr):
                a.run(Path('fixture.gpkg'),Path('fixture-baseline'))
        result=stdout.getvalue()
        self.assertIn('BATCH_STATUS=PASS',result)
        self.assertEqual(result.count('TEST_'),7)
        self.assertIn('CELL_VS_LAKES',result)

    def test_stage_failure_does_not_hide_other_results(self):
        def bad_ogr(gpkg, statement, expected_rows, label):
            raise ValueError('synthetic capability unavailable')
        with contextlib.redirect_stdout(io.StringIO()) as stdout:
            with mock.patch.object(a,'expect_files'), mock.patch.object(a,'csv_diagnostic'), mock.patch.object(a,'ogr',side_effect=bad_ogr):
                with self.assertRaisesRegex(ValueError,'PARTIAL_RESULTS'):
                    a.run(Path('fixture.gpkg'),Path('fixture-baseline'))
        output=stdout.getvalue()
        self.assertIn('TEST_02C_COMPONENT_AND_WATER_NEIGHBORS=PASS',output)
        self.assertIn('TEST_SYKE_7025519_GEOMETRY=STOP',output)
        self.assertIn('BATCH_STATUS=PARTIAL',output)
        self.assertTrue(output.endswith('=== TULOKSET LOPPUVAT ===\n'))


if __name__ == '__main__':
    unittest.main()
