"""Only temporary synthetic sources; no original CSC stat/read or pixel I/O."""
import ast
from contextlib import contextmanager, redirect_stdout
from dataclasses import asdict, FrozenInstanceError, replace
import csv
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import s2c_original_source_preflight as a


def write_csv(path, names, rows):
    with path.open('w',newline='',encoding='utf-8') as stream:
        out=csv.DictWriter(stream,fieldnames=names)
        out.writeheader();out.writerows(rows)


def read_csv(path):
    with path.open(newline='',encoding='utf-8') as stream:return list(csv.DictReader(stream))


def fake_metadata(role):
    proj=dict(type='ProjectedCRS',id={'authority':'EPSG','code':3067},
              base_crs=dict(id={'authority':'EPSG','code':10690},datum=dict(ellipsoid=dict(
                  semi_major_axis=6378137,inverse_flattening=298.257222101))),
              coordinate_system=dict(axis=[dict(direction='east',unit='metre'),dict(direction='north',unit='metre')]),
              conversion=dict(method=dict(id={'authority':'EPSG','code':9807}),parameters=[
                  dict(id=dict(code=k),unit=u,value=v) for k,u,v in
                  ((8801,'degree',0),(8802,'degree',27),(8805,'unity',0.9996),(8806,'metre',500000),(8807,'metre',0))]))
    dtype,nd={'pointer':('Float64',-9999),'water_class':('UInt16',65535),'lake_id':('Int32',-2147483648)}[role]
    return dict(driverShortName='GTiff',size=[6000,6000],geoTransform=[199000,2,0,6911000,0,-2],
                coordinateSystem=dict(wkt='PROJCRS["synthetic",ID["EPSG",3067]]',dataAxisToSRSAxisMapping=[1,2]),
                stac={'proj:projjson':proj},cornerCoordinates=dict(upperLeft=[199000,6911000],
                 lowerRight=[211000,6899000],center=[205000,6905000]),bands=[dict(band=1,type=dtype,noDataValue=nd)])


def fixture(root, real=False):
    request=a.Request(str(root),'SYNTHETIC')
    for name in ('01_inputs','02_baseline'):(request.run/name).mkdir(parents=True,exist_ok=True)
    source=root/'inputs'/'explicit-source-root'
    source.mkdir(parents=True)
    paths={name:request.run/relative for name,relative in a.CSV_FILES}
    raster=dict(pointer=request.run/'02_baseline/d8_pointer_land_water_FLT8S.tif',
                water_class=source/'ranta10_water_class.tif',lake_id=source/'ranta10_lake_id.tif')
    manifest=dict(pipeline_version='2.0-baseline-no-structures',run_mode='CSC_TEST',test_id=a.TILE,
                  pointer_scheme='whitebox',cell_size_m='2',stream_threshold_ha='4',
                  # DEM root is deliberately DIFFERENT, uncreated and never inspected.
                  dem=str(root/'uninspected-dem-root'/'dem_12km_rumpukorjattu.tif'),
                  ranta10_gpkg=str(source/'uninspected.gpkg'),lake_id_raster=str(raster['lake_id']),
                  river_area_raster=str(source/'uninspected-river-area.tif'),
                  river_line_raster=str(source/'uninspected-river-line.tif'),water_class_raster=str(raster['water_class']),
                  water_mask_raster=str(source/'uninspected-water-mask.tif'),
                  lake_elevation_raster=str(request.run/'01_inputs'/'uninspected-lake-elevation.tif'))
    write_csv(paths['manifest'],('key','value'),[dict(key=k,value=manifest[k]) for k in a.MANIFEST_KEYS])
    qa=dict(a.QA_VALUES)
    qa.update({k:1 for k in a.QA_KEYS if k not in qa})
    write_csv(paths['qa'],('item','value'),[dict(item=k,value=qa[k]) for k in a.QA_KEYS])
    routes=[dict(zip(a.ROUTE_FIELDS,(rid,start,1894,a.TERMINAL,None,None,steps,'D8_ZERO_INTERIOR')))
            for rid,start,steps in a.EXPECTED]
    # Invented unselected summary makes sure the WHOLE file participates in hashes.
    routes.append(dict(zip(a.ROUTE_FIELDS,(99,6001,99,6001,None,None,0,'D8_ZERO_INTERIOR'))))
    write_csv(paths['routes'],a.ROUTE_FIELDS,routes)
    # Invented neighbor coordinates. Not claimed as the real three 02C cell IDs.
    neighbors=[dict(component_id=274,source_cell=a.TERMINAL,water_cell=cell,water_class=1,
                    lake_objectid=1892,water_z_m=1.5) for cell in (23211318,23211320,23205318)]
    write_csv(paths['neighbors'],a.NEIGHBOR_FIELDS,neighbors)
    write_csv(paths['zero_cells'],a.ZERO_FIELDS,[dict(cell=a.TERMINAL,component_id=274,x=205637,
                                                    y=6903263,z_m=2.5,raster_edge='FALSE')])
    if real:
        # Reuse ONLY the existing stdlib synthetic TIFF WRITER. No raster reader.
        import test_s2b_readonly_window_adapter as writer
        data,_=writer.fixtures.six_fixture(True)
        for role,path in raster.items():writer.tiny_geotiff(path,getattr(data,role),role)
    else:
        for path in raster.values():path.write_bytes(b'SYNTHETIC_METADATA_ONLY_PLACEHOLDER')
    return request,paths,raster


class Backend:
    def __init__(self,rasters):
        self.rasters=rasters;self.calls=[];self.mutation=None
        self.version=b'GDAL 3.12.2 "Chicoutimi", released 2026/02/03\n'

    def command(self,runner,args):
        self.calls.append(args);runner.calls+=1
        if args[-1]=='--version':return self.version
        role=next(k for k,v in self.rasters.items() if str(v)==args[-1])
        raw=fake_metadata(role)
        if self.mutation:self.mutation(raw,role)
        result=json.dumps(raw).encode()
        runner.stdout_bytes+=len(result)
        return result

    @contextmanager
    def installed(self):
        with patch.object(a.InfoOnly,'command',autospec=True,side_effect=self.command):yield


class Case(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='mm-s2c-synthetic-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.request,self.paths,self.rasters=fixture(self.root)
        self.backend=Backend(self.rasters)

    def run_mock(self):
        with self.backend.installed():return a.preflight(self.request,'/usr/bin/gdalinfo')

    def stop(self,text):
        report=self.run_mock()
        self.assertEqual(report.metadata_status,'STOP',a.framed(report))
        self.assertIn(text,report.error)
        self.assertIs(report.routing_authorized,False)
        return report

    def edit_manifest(self,key,value):
        rows=read_csv(self.paths['manifest'])
        for row in rows:
            if row['key']==key:row['value']=value
        write_csv(self.paths['manifest'],('key','value'),rows)


class NativeSourceTests(Case):
    def test_metadata_complete_still_stops_for_missing_runtime_link(self):
        r=self.run_mock()
        self.assertEqual(r.metadata_status,'PASS',r.error)
        self.assertEqual(r.overall_status,'STOP')
        self.assertEqual(dict(r.stages)['RUNTIME_INPUT_LINEAGE'],'STOP')
        self.assertTrue(all(v=='PASS' for k,v in r.stages if k!='RUNTIME_INPUT_LINEAGE'))
        self.assertEqual(r.RUNTIME_INPUT_LINEAGE,'NOT_ASSESSED')
        self.assertEqual(r.RUNTIME_PRODUCER_COMMIT,'UNKNOWN')
        self.assertEqual(r.SOURCE_AUTHENTICATION,'NOT_ASSESSED')

    def test_only_fixed_csv_reads_and_three_metadata_commands(self):
        opened=[]
        original=a.os.open
        def observe(path,flags,*args,**kwargs):
            opened.append((str(path),flags));return original(path,flags,*args,**kwargs)
        with patch.object(a.os,'open',side_effect=observe):r=self.run_mock()
        self.assertEqual({p for p,_ in opened},{str(p) for p in self.paths.values()})
        self.assertTrue(all(flags & os.O_WRONLY==0 and flags & os.O_RDWR==0 for _,flags in opened))
        self.assertEqual(len(self.backend.calls),4)
        self.assertEqual(self.backend.calls[1:],[("/usr/bin/gdalinfo",)+a.METADATA_FLAGS+(str(self.rasters[k]),)
                                               for k in ('pointer','water_class','lake_id')])
        self.assertEqual(r.raster_pixel_reads,0)
        self.assertEqual(r.S2A_REPLAY,'NOT_RUN')
        self.assertEqual(r.TRUE_02F_CONTINUITY,'NOT_RUN')

    def test_manifest_source_root_is_independent_of_dem_directory(self):
        r=self.run_mock()
        self.assertEqual(r.metadata_status,'PASS')
        self.assertFalse((self.root/'uninspected-dem-root').exists())
        self.assertEqual([x.version.path for x in r.raster_metadata],[str(v) for v in self.rasters.values()])
        self.assertIn('CANDIDATE',r.raster_metadata[0].path_basis)

    def test_hashes_cover_complete_supplied_small_files(self):
        r=self.run_mock()
        self.assertEqual(len(r.csv_versions),5)
        for item in r.csv_versions:
            self.assertEqual(item.sha256,a.sha256(Path(item.version.path).read_bytes()).hexdigest())
            self.assertEqual(item.version.size_bytes,Path(item.version.path).stat().st_size)
        self.assertFalse(r.historic_02f_sha256_match)
        self.assertEqual(r.SOURCE_AUTHENTICATION,'NOT_ASSESSED')
        self.assertTrue(all(x.raster_content_sha256=='NOT_CHECKED' for x in r.raster_metadata))

    def test_expected_hash_mismatch_stops_before_gdal(self):
        self.request=replace(self.request,expected_hashes=(('routes','b'*64),))
        r=self.stop('EXPECTED_CSV_SHA256_MISMATCH routes')
        self.assertEqual(self.backend.calls,[])
        self.assertTrue(any(x.role=='routes' for x in r.csv_versions))

    def test_matching_operator_hash_never_authenticates_source(self):
        h=a.sha256(self.paths['routes'].read_bytes()).hexdigest()
        self.request=replace(self.request,expected_hashes=(('routes',h),))
        r=self.run_mock()
        self.assertEqual(r.metadata_status,'PASS')
        self.assertEqual(r.SOURCE_AUTHENTICATION,'NOT_ASSESSED')
        self.assertFalse(r.routing_authorized)

    def test_altered_unselected_csv_bytes_detected_by_pin(self):
        h=a.sha256(self.paths['routes'].read_bytes()).hexdigest()
        self.request=replace(self.request,expected_hashes=(('routes',h),))
        self.paths['routes'].write_bytes(self.paths['routes'].read_bytes()+b'\n')
        self.stop('EXPECTED_CSV_SHA256_MISMATCH')

    def test_no_bytes_names_or_modification_times_change(self):
        before={str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in (*self.paths.values(),*self.rasters.values())}
        self.run_mock()
        self.assertEqual(before,{str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in (*self.paths.values(),*self.rasters.values())})

    def test_missing_original_pointer_has_no_search_or_substitution(self):
        self.rasters['pointer'].unlink()
        r=self.stop('No such file')
        self.assertEqual(dict(r.stages)['RASTER_METADATA'],'NOT_RUN')
        self.assertEqual(self.backend.calls,[])

    def test_native_manifest_variant_is_rejected_with_actual_fields(self):
        self.paths['manifest'].write_text('item,value\nkey,anything\n')
        r=self.stop('CSV_SCHEMA 01_manifest')
        self.assertIn('actual_fieldnames=["item", "value"]',r.error)
        self.assertEqual(r.csv_versions[0].fieldnames,('item','value'))

    def test_unknown_commit_claim_is_recorded_but_not_authenticated(self):
        rows=read_csv(self.paths['manifest'])
        rows.append(dict(key='producer_commit',value='a'*40))
        write_csv(self.paths['manifest'],('key','value'),rows)
        r=self.stop('NATIVE_KEYS')
        self.assertIn(('producer_commit','a'*40),r.manifest_entries)
        self.assertEqual(r.RUNTIME_PRODUCER_COMMIT,'UNKNOWN')
        self.assertEqual(self.backend.calls,[])

    def test_duplicate_manifest_key_is_not_last_wins(self):
        rows=read_csv(self.paths['manifest']);rows.append(rows[0])
        write_csv(self.paths['manifest'],('key','value'),rows)
        self.stop('DUPLICATE_KEY')

    def test_manifest_national_or_other_tile_is_rejected(self):
        self.edit_manifest('run_mode','NATIONAL');self.stop('NATIVE_MANIFEST_LOW_CONFIGURATION')
        self.edit_manifest('run_mode','CSC_TEST');self.edit_manifest('test_id','E212000_N6900000')
        self.stop('NATIVE_MANIFEST_LOW_CONFIGURATION')

    def test_wrong_pointer_convention(self):
        self.edit_manifest('pointer_scheme','esri');self.stop('NATIVE_MANIFEST_LOW_CONFIGURATION')

    def test_water_and_lake_must_share_code_compatible_source_root(self):
        self.edit_manifest('water_class_raster',str(self.root/'another'/'ranta10_water_class.tif'))
        self.stop('SOURCE_TEST_ROOT_CONTRACT')

    def test_qa_variant_and_extra_keys_not_silently_adapted(self):
        rows=read_csv(self.paths['qa']);rows.append(dict(item='epsg',value='3067'))
        write_csv(self.paths['qa'],('item','value'),rows)
        self.stop('NATIVE_KEYS 01_QA')

    def test_wrong_qa_geometry(self):
        rows=read_csv(self.paths['qa'])
        rows[0]['value']='5999'
        write_csv(self.paths['qa'],('item','value'),rows)
        self.stop('INPUT_QA_LOW_GEOMETRY')

    def test_full_selected_route_identities_and_three_actual_csv_neighbors(self):
        r=self.run_mock()
        self.assertEqual(tuple(x[0] for x in r.selected_routes),(11,14,15,16,18,20))
        self.assertEqual(tuple(x[6] for x in r.selected_routes),(21,22,22,23,23,24))
        self.assertEqual(r.full_route_count,7)
        self.assertEqual(len(r.selected_neighbors),3)
        self.assertEqual({x[2] for x in r.selected_neighbors},{23211318,23211320,23205318})

    def test_changed_route_start_steps_terminal_or_status(self):
        original=read_csv(self.paths['routes'])
        for key,value in (('start_receiver_cell','23337319'),('route_steps','20'),('terminal_cell','23211320'),
                          ('origin_lake_objectid','1892'),('terminal_water_class','1'),('route_status','VALIDATED')):
            rows=[r.copy() for r in original];rows[0][key]=value
            write_csv(self.paths['routes'],a.ROUTE_FIELDS,rows)
            with self.subTest(key=key):self.stop('CONTRADICTORY_02F_IDENTITY')

    def test_duplicate_or_missing_route_id(self):
        original=read_csv(self.paths['routes']);rows=[r.copy() for r in original];rows[1]['route_id']='11'
        write_csv(self.paths['routes'],a.ROUTE_FIELDS,rows);self.stop('DUPLICATE_OR_INVALID_ROUTE_ID')
        write_csv(self.paths['routes'],a.ROUTE_FIELDS,original[1:]);self.stop('MISSING_PINNED_ROUTE')

    def test_route_schema_alias_has_no_silent_repair(self):
        raw=self.paths['routes'].read_text().replace('start_receiver_cell','receiver_cell',1)
        self.paths['routes'].write_text(raw)
        r=self.stop('CSV_SCHEMA 02F')
        self.assertIn('receiver_cell',r.error)

    def test_02c_changed_source_lake_or_nonadjacent_neighbor(self):
        original=read_csv(self.paths['neighbors'])
        for key,value in (('source_cell','23211320'),('lake_objectid','1894'),('water_class','2'),('water_cell','36000000')):
            rows=[r.copy() for r in original];rows[0][key]=value
            write_csv(self.paths['neighbors'],a.NEIGHBOR_FIELDS,rows)
            with self.subTest(key=key):self.stop('NONADJACENT' if key=='water_cell' else 'CONTRADICTORY_02C_IDENTITY')

    def test_02c_duplicate_missing_and_zero_record_contradiction(self):
        rows=read_csv(self.paths['neighbors']);rows[1]=rows[0].copy()
        write_csv(self.paths['neighbors'],a.NEIGHBOR_FIELDS,rows);self.stop('THREE_UNIQUE')
        rows=rows[:2];write_csv(self.paths['neighbors'],a.NEIGHBOR_FIELDS,rows);self.stop('THREE_UNIQUE')

    def test_terminal_zero_component_coordinates_and_edge_flag(self):
        original=read_csv(self.paths['zero_cells'])
        for key,value in (('component_id','275'),('x','205638'),('y','6903262'),('raster_edge','TRUE')):
            rows=[r.copy() for r in original];rows[0][key]=value
            write_csv(self.paths['zero_cells'],a.ZERO_FIELDS,rows)
            with self.subTest(key=key):self.stop('CONTRADICTORY_TERMINAL_ZERO_RECORD')

    def test_utf8_bom_is_explicitly_supported_native_csv(self):
        p=self.paths['manifest'];p.write_bytes(b'\xef\xbb\xbf'+p.read_bytes())
        self.assertEqual(self.run_mock().metadata_status,'PASS')


class SecurityTests(Case):
    def test_original_request_is_fixed_without_accessing_csc(self):
        with patch('os.lstat',side_effect=AssertionError('must not inspect CSC')):
            req=a.Request()
            self.assertEqual(req.run,a.RUN)
            with self.assertRaises(a.Stop):a.Request('/scratch/other')
        self.assertEqual(self.backend.calls,[])

    def test_escape_and_other_tile_paths_fail_before_metadata(self):
        for path in ('/etc/ranta10_water_class.tif',str(self.root/'..'/'ranta10_water_class.tif'),
                     str(self.root/'E212000_N6900000'/'ranta10_water_class.tif')):
            self.edit_manifest('water_class_raster',path)
            with self.subTest(path=path):
                r=self.run_mock();self.assertEqual(r.metadata_status,'STOP');self.assertEqual(self.backend.calls,[])

    def test_both_manifest_paths_outside_project_are_rejected(self):
        for role in ('water_class','lake_id'):
            self.edit_manifest(role+'_raster','/etc/ranta10_'+role+'.tif')
        self.stop('PATH_OUTSIDE_PROJECT')

    def test_symlink_file_and_ancestor(self):
        p=self.rasters['water_class'];real=p.with_name('real.tif');p.rename(real);p.symlink_to(real)
        self.stop('SYMLINK_OR_ANCESTOR');p.unlink();real.rename(p)
        source=p.parent;other=source.with_name('renamed');source.rename(other);source.symlink_to(other,target_is_directory=True)
        self.stop('SYMLINK_OR_ANCESTOR')

    def test_hardlink_rejected(self):
        os.link(self.rasters['pointer'],self.root/'another.tif');self.stop('REGULAR_UNALIASED_FILE_REQUIRED')

    def test_large_small_file_rejected_without_whole_read(self):
        self.paths['routes'].write_bytes(b'x'*(a.SMALL_LIMIT+1))
        self.stop('SMALL_FILE_SIZE_LIMIT');self.assertEqual(self.backend.calls,[])

    def test_csv_fanout_limit(self):
        rows=read_csv(self.paths['routes'])
        write_csv(self.paths['routes'],a.ROUTE_FIELDS,[rows[0]]*20001)
        self.assertLessEqual(self.paths['routes'].stat().st_size,a.SMALL_LIMIT)
        self.stop('CSV_FANOUT_LIMIT')

    def test_header_fanout_is_bounded_in_stop_report(self):
        self.paths['routes'].write_text(','.join('field'+str(i) for i in range(1000))+'\n')
        r=self.stop('CSV_HEADER_RESOURCE_LIMIT')
        text=a.framed(r)
        self.assertLess(len(text.encode()),a.REPORT_LIMIT)
        self.assertEqual(next(x for x in r.csv_versions if x.role=='routes').fieldnames,('HEADER_EXCEEDS_RESOURCE_LIMIT',))

    def test_mutation_during_gdal_is_detected(self):
        original=self.backend.command
        def changed(runner,args):
            raw=original(runner,args)
            if '--version' not in args:self.rasters['pointer'].write_bytes(b'changed')
            return raw
        with patch.object(a.InfoOnly,'command',autospec=True,side_effect=changed):r=a.preflight(self.request,'/usr/bin/gdalinfo')
        self.assertIn('SOURCE_CHANGED',r.error)
        self.assertEqual(r.overall_status,'STOP')

    def test_mutation_of_csv_during_gdal_detected_at_end(self):
        original=self.backend.command
        def changed(runner,args):
            raw=original(runner,args)
            if '--version' not in args:
                with self.paths['routes'].open('a') as stream:stream.write('\n')
            return raw
        with patch.object(a.InfoOnly,'command',autospec=True,side_effect=changed):r=a.preflight(self.request,'/usr/bin/gdalinfo')
        self.assertIn('SOURCE_CHANGED',r.error)

    def test_no_directory_scans_r_hash_scans_or_raster_open(self):
        with patch('os.scandir',side_effect=AssertionError('no scans')), \
             patch.object(a.Path,'glob',side_effect=AssertionError('no glob')), \
             patch.object(a.Path,'rglob',side_effect=AssertionError('no recursive glob')):
            r=self.run_mock()
        self.assertEqual(r.metadata_status,'PASS')
        # Only CSV files are opened by Python. gdalinfo receives three fixed paths.
        self.assertEqual(r.raster_pixel_reads,0)

    def test_invalid_and_duplicate_hash_bindings_fail_closed(self):
        for bindings in ((('routes','g'*64),),(('routes','a'*64),('routes','b'*64)),(('arbitrary','a'*64),)):
            with self.subTest(bindings=bindings),self.assertRaises(a.Stop):replace(self.request,expected_hashes=bindings)


class MetadataTests(Case):
    def mutated(self,fn,reason):
        self.backend.mutation=fn;return self.stop(reason)

    def test_wrong_version_stops_before_raster_metadata(self):
        self.backend.version=b'GDAL 3.10.3, released 2025/04/01\n'
        self.stop('GDAL_3_12_2_REQUIRED');self.assertEqual(len(self.backend.calls),1)

    def test_wrong_crs(self):
        self.mutated(lambda m,r:m['coordinateSystem'].update(wkt='PROJCRS["x",ID["EPSG",4326]]'),'CRS_OR_AXIS_MAPPING')

    def test_3067_label_with_wrong_projection_is_not_enough(self):
        self.mutated(lambda m,r:m['stac']['proj:projjson']['conversion']['parameters'][1].update(value=28),'PROJECTION_PARAMETERS')

    def test_wrong_units_or_ellipsoid(self):
        self.mutated(lambda m,r:m['stac']['proj:projjson']['coordinate_system']['axis'][0].update(unit='foot'),'PROJECTED_UNITS_OR_AXES')
        self.backend.mutation=lambda m,r:m['stac']['proj:projjson']['base_crs']['datum']['ellipsoid'].update(semi_major_axis=6371000)
        self.stop('BASE_CRS_OR_ELLIPSOID')

    def test_missing_structured_crs_is_stop(self):
        self.mutated(lambda m,r:m.pop('stac'),'PROJJSON_CRS')

    def test_etrs89_base_variant_supported_explicitly(self):
        self.backend.mutation=lambda m,r:m['stac']['proj:projjson']['base_crs'].update(id={'authority':'EPSG','code':4258})
        self.assertEqual(self.run_mock().metadata_status,'PASS')

    def test_wrong_dimensions_affine_resolution_or_extent(self):
        for fn,reason in ((lambda m,r:m.update(size=[6000,5999]),'DRIVER_OR_DIMENSIONS'),
                          (lambda m,r:m.update(geoTransform=[199000,1,0,6911000,0,-2]),'GEOTRANSFORM_OR_RESOLUTION'),
                          (lambda m,r:m['cornerCoordinates'].update(center=[0,0]),'EXTENT_OR_CENTER')):
            with self.subTest(reason=reason):self.mutated(fn,reason)

    def test_boolean_numeric_metadata_is_not_valid_geometry(self):
        for fn,reason in ((lambda m,r:m['geoTransform'].__setitem__(2,False),'GEOTRANSFORM_OR_RESOLUTION'),
                          (lambda m,r:m['stac']['proj:projjson']['conversion']['parameters'][0].update(value=False),'PROJECTION_PARAMETERS'),
                          (lambda m,r:m['bands'][0].update(scale=True),'SCALE_OFFSET_MASK_OR_OVERVIEW')):
            with self.subTest(reason=reason):self.mutated(fn,reason)

    def test_wrong_band_count(self):
        self.mutated(lambda m,r:m['bands'].append(m['bands'][0].copy()),'BAND_COUNT')

    def test_pointer_dtype_matches_actual_float64_producer(self):
        self.mutated(lambda m,r:m['bands'][0].update(type='Float32') if r=='pointer' else None,'DTYPE_OR_POINTER_NOT_FLT8S')

    def test_complex_dtype_rejected(self):
        self.mutated(lambda m,r:m['bands'][0].update(type='CFloat64'),'DTYPE_OR_POINTER_NOT_FLT8S')

    def test_zero_pointer_nodata_is_stop_without_value_read(self):
        r=self.mutated(lambda m,r:m['bands'][0].update(noDataValue=0) if r=='pointer' else None,'AMBIGUOUS_ZERO_POINTER_NODATA')
        self.assertEqual(r.raster_pixel_reads,0)

    def test_nonzero_pointer_nodata_and_nan_are_recorded_not_values(self):
        self.assertEqual(self.run_mock().raster_metadata[0].nodata,-9999)
        self.backend.mutation=lambda m,r:m['bands'][0].update(noDataValue='NaN') if r=='pointer' else None
        r=self.run_mock();self.assertEqual(r.metadata_status,'PASS');self.assertEqual(r.raster_metadata[0].nodata,'NaN')

    def test_missing_nodata_is_not_inferred(self):
        self.mutated(lambda m,r:m['bands'][0].pop('noDataValue'),'EXPLICIT_FINITE_OR_NAN_NODATA_REQUIRED')

    def test_nodata_must_match_dtype_range(self):
        self.mutated(lambda m,r:m['bands'][0].update(noDataValue=-9999) if r=='water_class' else None,'NODATA_DTYPE_RANGE')

    def test_water_and_lake_nodata_do_not_hide_valid_ids(self):
        self.mutated(lambda m,r:m['bands'][0].update(noDataValue=1) if r=='water_class' else None,'VALID_WATER_CLASS_AS_NODATA')
        self.backend.mutation=lambda m,r:m['bands'][0].update(noDataValue=1892) if r=='lake_id' else None
        self.stop('POSITIVE_LAKE_ID_AS_NODATA')

    def test_scaled_masked_or_overview_sources_stop(self):
        for key,value in (('scale',2),('offset',1),('mask',{'flags':['PER_DATASET']}),('overviews',[{}])):
            with self.subTest(key=key):self.mutated(lambda m,r:m['bands'][0].update({key:value}),'SCALE_OFFSET_MASK_OR_OVERVIEW')

    def test_oversized_or_multiline_version_cannot_amplify_report(self):
        for value in (b'GDAL 3.12.2 '+b'x'*1000,b'GDAL 3.12.2\nextra line'):
            self.backend.version=value
            with self.subTest(length=len(value)):self.stop('GDAL_3_12_2_REQUIRED')

    def test_duplicate_json_keys_and_nonfinite_json(self):
        for raw in (b'{"size":1,"size":2}',b'{"size":NaN}'):
            with self.subTest(raw=raw),self.assertRaises(a.Stop):a.metadata(raw,'pointer')


class CommandTests(unittest.TestCase):
    def runner(self):return a.InfoOnly('/usr/bin/gdalinfo',('/tmp/a.tif','/tmp/b.tif','/tmp/c.tif'))

    def test_explicit_present_proj_database_is_selected(self):
        with tempfile.TemporaryDirectory() as root:
            db = Path(root) / 'data'
            db.mkdir()
            (db / 'proj.db').write_bytes(b'SYNTHETIC_DB_ONLY')
            with patch.dict(a.os.environ, {'PROJ_DATA': str(db), 'PROJ_LIB': ''}):
                self.assertEqual(a.find_proj_data('/unused/bin/gdalinfo'), str(db.resolve()))

    def test_invalid_primary_path_falls_back_to_valid_proj_lib(self):
        with tempfile.TemporaryDirectory() as root:
            good = Path(root) / 'valid'
            good.mkdir()
            (good / 'proj.db').write_bytes(b'SYNTHETIC_DB_ONLY')
            with patch.dict(a.os.environ, {'PROJ_DATA': str(Path(root) / 'missing'),
                                            'PROJ_LIB': str(good)}):
                self.assertEqual(a.find_proj_data('/unused/bin/gdalinfo'), str(good.resolve()))

    def test_missing_database_does_not_forward_unverified_path(self):
        with tempfile.TemporaryDirectory() as root:
            exe = str(Path(root) / 'fake' / 'bin' / 'gdalinfo')
            with patch.dict(a.os.environ, {'PROJ_DATA': str(Path(root) / 'bad'),
                                            'PROJ_LIB': ''}), patch.object(a.sys, 'prefix', str(Path(root) / 'python')):
                self.assertIsNone(a.find_proj_data(exe))

    def test_isolated_process_receives_only_verified_proj_data(self):
        with patch.object(a, 'find_proj_data', return_value='/opt/test-proj') as locate:
            runner = self.runner()
        self.assertEqual(runner.proj_data, '/opt/test-proj')
        locate.assert_called_once_with('/usr/bin/gdalinfo')
        def observed(args, **kw):
            env = kw['env']
            self.assertEqual(env['PROJ_DATA'], '/opt/test-proj')
            self.assertEqual(env['PROJ_NETWORK'], 'OFF')
            self.assertEqual(env['GDAL_PAM_ENABLED'], 'NO')
            self.assertEqual(env['GDAL_DRIVER_PATH'], 'disable')
            self.assertNotIn('GTIFF_SRS_SOURCE', env)
            self.assertNotIn('HOME', env)
            return self.fake()(args, **kw)
        with patch.object(a.subprocess, 'run', side_effect=observed):
            self.assertEqual(runner.command((runner.executable, '--version')), b'GDAL 3.12.2')

    def test_warnings_still_stop_with_proj_data_selected(self):
        with patch.object(a, 'find_proj_data', return_value='/opt/test-proj'):
            runner = self.runner()
        with patch.object(a.subprocess, 'run', side_effect=self.fake(err=b'Warning 1: test')):
            with self.assertRaisesRegex(a.Stop, 'GDALINFO_EXIT_OR_WARNING'):
                runner.command((runner.executable, '--version'))

    def fake(self,out=b'GDAL 3.12.2',err=b'',code=0):
        def run(args,**kw):
            self.assertIs(kw['shell'],False);self.assertLessEqual(kw['timeout'],10)
            self.assertNotIn('capture_output',kw);self.assertEqual(kw['env']['GDAL_PAM_ENABLED'],'NO')
            self.assertEqual(kw['env']['PROJ_NETWORK'],'OFF')
            for fd,payload in ((kw['stdout'],out),(kw['stderr'],err)):
                try:
                    if payload:os.write(fd,payload)
                except BrokenPipeError:pass
            return subprocess.CompletedProcess(args,code)
        return run

    def test_only_gdalinfo_metadata_and_version_argv_are_allowed(self):
        runner=self.runner()
        allowed=(runner.executable,)+a.METADATA_FLAGS+('/tmp/a.tif',)
        with patch.object(a.subprocess,'run',side_effect=self.fake()) as process:
            self.assertEqual(runner.command(allowed),b'GDAL 3.12.2');self.assertEqual(process.call_count,1)

    def test_stats_checksum_histogram_and_other_paths_forbidden(self):
        runner=self.runner()
        for flags in (('-stats',),('-approx_stats',),('-mm',),('-hist',),('-checksum',),('-json','/etc/a.tif')):
            with self.subTest(flags=flags),patch.object(a.subprocess,'run') as process,self.assertRaises(a.Stop):
                runner.command((runner.executable,)+flags)
            process.assert_not_called()

    def test_translate_warp_shell_or_value_reader_forbidden(self):
        for executable in ('/usr/bin/gdal_translate','/usr/bin/gdalwarp','/bin/sh'):
            with self.subTest(executable=executable),self.assertRaises(a.Stop):a.InfoOnly(executable,('/tmp/a','/tmp/b','/tmp/c'))
        with self.assertRaises(a.Stop):self.runner().command(('/usr/bin/gdalinfo','-srcwin','3293','3844','52','73'))

    def test_oversized_stdout_and_stderr_are_bounded_while_collecting(self):
        for payloads in ((b'x'*2049,b''),(b'',b'x'*2049)):
            with patch.object(a,'OUT_LIMIT',2048),patch.object(a,'ERR_LIMIT',2048), \
                 patch.object(a.subprocess,'run',side_effect=self.fake(*payloads)):
                with self.assertRaisesRegex(a.Stop,'OUTPUT_SIZE_LIMIT'):self.runner().command(('/usr/bin/gdalinfo','--version'))

    def test_timeout_has_no_retry(self):
        with patch.object(a.subprocess,'run',side_effect=subprocess.TimeoutExpired('gdalinfo',10)) as process:
            with self.assertRaisesRegex(a.Stop,'TIMEOUT'):self.runner().command(('/usr/bin/gdalinfo','--version'))
            self.assertEqual(process.call_count,1)

    def test_failure_and_warning_do_not_trigger_fallback(self):
        for err,code in ((b'warning',0),(b'',1)):
            with patch.object(a.subprocess,'run',side_effect=self.fake(err=err,code=code)) as process:
                with self.assertRaisesRegex(a.Stop,'EXIT_OR_WARNING'):self.runner().command(('/usr/bin/gdalinfo','--version'))
                self.assertEqual(process.call_count,1)

    def test_fanout_and_deadline_stop_before_process(self):
        for count,deadline in ((4,10**20),(0,0)):
            r=self.runner();r.calls=count;r.deadline=deadline
            with patch.object(a.subprocess,'run') as process,self.assertRaises(a.Stop):r.command(('/usr/bin/gdalinfo','--version'))
            process.assert_not_called()

    def test_module_has_no_raster_value_or_network_dependencies(self):
        tree=ast.parse(Path(a.__file__).read_text())
        names={alias.name for n in ast.walk(tree) if isinstance(n,ast.Import) for alias in n.names}
        names|={n.module for n in ast.walk(tree) if isinstance(n,ast.ImportFrom)}
        self.assertFalse(names & {'osgeo','rasterio','terra','numpy','socket','urllib','requests',
                                 's2a_pure_d8_trace','s2b_readonly_window_adapter'})
        self.assertNotIn('gdal_translate',Path(a.__file__).read_text())


class ReportTests(Case):
    def test_exactly_one_pair_of_finnish_markers_and_compact_json(self):
        text=a.framed(self.run_mock())
        self.assertEqual(text.count('=== TULOKSET ALKAVAT ==='),1)
        self.assertEqual(text.count('=== TULOKSET LOPPUVAT ==='),1)
        data=json.loads(text.splitlines()[1])
        self.assertEqual(data['raster_pixel_reads'],0)
        self.assertEqual(data['future_window'],[3293,3844,52,73])
        self.assertLess(len(text.encode()),a.REPORT_LIMIT)

    def test_locks_are_frozen_and_never_claim_scientific_acceptance(self):
        r=self.run_mock()
        self.assertEqual((r.NATIONAL,r.MODERATE,r.hydrological_validation,r.channel_interpretation),
                         ('LOCKED','REVIEW_REQUIRED','NOT_ASSESSED','NOT_ASSESSED'))
        with self.assertRaises(FrozenInstanceError):r.routing_authorized=True
        # dataclasses.replace(init=False=...) raises ValueError on older Python,
        # TypeError on Python 3.14; both must reject spoofed authentication.
        with self.assertRaises((TypeError, ValueError)):
            replace(r, SOURCE_AUTHENTICATION='PASS')
        self.assertEqual(r.SOURCE_AUTHENTICATION, 'NOT_ASSESSED')
        self.assertFalse(r.routing_authorized);self.assertEqual(r.outlet_selection,'UNASSIGNED')

    def test_cli_is_framed_exit_two_and_never_executes_original_in_tests(self):
        r=self.run_mock();stream=io.StringIO()
        with patch.object(a,'preflight',return_value=r) as pre,redirect_stdout(stream):code=a.main([])
        self.assertEqual(code,2);self.assertEqual(pre.call_count,1)
        self.assertEqual(stream.getvalue(),a.framed(r))

    def test_cli_invalid_hash_or_output_path_does_not_touch_original_files(self):
        for argv in (['--expect-02f-sha256','bad'],['--output','anything'],['--run-root','/scratch/other']):
            with self.subTest(argv=argv),patch.object(a,'preflight') as pre,redirect_stdout(io.StringIO()) as out:
                code=a.main(argv)
                self.assertEqual(code,2);pre.assert_not_called()
                self.assertEqual(out.getvalue().count('=== TULOKSET ALKAVAT ==='),1)

    def test_untrusted_marker_text_cannot_inject_framing(self):
        tag='=== TULOKSET ALKAVAT ==='
        r=replace(self.run_mock(),manifest_entries=(('uninspected',tag),))
        text=a.framed(r)
        self.assertEqual(text.count(tag),1)
        self.assertEqual(json.loads(text.splitlines()[1])['manifest_entries'][0][1],tag)

    def test_total_timeout_is_reported_and_alarm_restored(self):
        with patch.object(a,'preflight',side_effect=a.Stop('TOTAL_PREFLIGHT_TIMEOUT')), \
             patch.object(a.signal,'alarm',return_value=0) as alarm, \
             patch.object(a.signal,'signal') as handler,redirect_stdout(io.StringIO()) as out:
            self.assertEqual(a.main([]),2)
            self.assertIn('TOTAL_PREFLIGHT_TIMEOUT',out.getvalue())
            self.assertEqual(alarm.call_args_list[0].args,(60,))
            self.assertEqual(alarm.call_args_list[-1].args,(0,))
            self.assertEqual(handler.call_count,2)

    def test_oversized_report_is_framed_stop_not_partial_output(self):
        r=replace(self.run_mock(),manifest_entries=(('amplified','😀'*20000),))
        text=a.framed(r);obj=json.loads(text.splitlines()[1])
        self.assertEqual(obj['metadata_status'],'STOP');self.assertIn('DETAILS_OMITTED',obj['error'])
        self.assertLess(len(text.encode()),a.REPORT_LIMIT)
        self.assertFalse(obj['routing_authorized'])


GDAL_READY=False
if os.environ.get('MM_S2C_GDAL_TESTS')=='1' and shutil.which('gdalinfo'):
    v=subprocess.run(['gdalinfo','--version'],capture_output=True,text=True,timeout=5)
    GDAL_READY=bool(a.re.match(r'^GDAL 3\.12\.2(?:[ ,]|$)',v.stdout))


@unittest.skipUnless(GDAL_READY,'NOT_RUN: set MM_S2C_GDAL_TESTS=1 in GDAL 3.12.2 environment')
class ActualMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='mm-s2c-synthetic-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.request,self.paths,self.rasters=fixture(self.root,real=True)

    def test_actual_gdalinfo_only_and_unchanged_synthetic_sources(self):
        before={str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in (*self.paths.values(),*self.rasters.values())}
        original=a.subprocess.run
        calls=[]
        def observe(args,**kwargs):calls.append(args);return original(args,**kwargs)
        with patch.object(a.subprocess,'run',side_effect=observe):r=a.preflight(self.request,shutil.which('gdalinfo'))
        self.assertEqual(r.metadata_status,'PASS',a.framed(r))
        self.assertEqual(len(calls),4)
        self.assertTrue(all(Path(args[0]).name=='gdalinfo' for args in calls))
        self.assertEqual(r.raster_pixel_reads,0);self.assertEqual(r.RUNTIME_INPUT_LINEAGE,'NOT_ASSESSED')
        self.assertEqual(before,{str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in (*self.paths.values(),*self.rasters.values())})

    def test_actual_zero_nodata_and_wrong_crs_are_metadata_stops(self):
        import test_s2b_readonly_window_adapter as writer
        values=writer.fixtures.six_fixture(True)[0].pointer
        writer.tiny_geotiff(self.rasters['pointer'],values,'pointer',nodata={'kind':'FINITE','value':0})
        r=a.preflight(self.request,shutil.which('gdalinfo'))
        self.assertIn('AMBIGUOUS_ZERO_POINTER',r.error);self.assertEqual(r.raster_pixel_reads,0)
        writer.tiny_geotiff(self.rasters['pointer'],values,'pointer',epsg=3857)
        r=a.preflight(self.request,shutil.which('gdalinfo'))
        self.assertIn('CRS_OR_AXIS_MAPPING',r.error)


if __name__=='__main__':unittest.main()
