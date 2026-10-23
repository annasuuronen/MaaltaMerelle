"""Synthetic/adversarial S2B tests; all writes are disposable fixture files.

Only the optional real-GDAL class needs GDAL 3.12.2 CLI. No Python GIS library,
actual CSC file, full-grid array, network access or output raster is used.
"""
from contextlib import contextmanager
import csv
from dataclasses import asdict, fields, replace, FrozenInstanceError
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

import s2a_pure_d8_trace as s
import s2b_readonly_window_adapter as a
import test_s2a_pure_d8_trace as fixtures

NODATA = {"pointer": {"kind":"FINITE","value":-9999},
          "water_class": {"kind":"FINITE","value":65535},
          "lake_id": {"kind":"FINITE","value":-2147483648}}
DTYPES = {"pointer":"Float64", "water_class":"UInt16", "lake_id":"Int32"}


def digest(path):
    return a.sha256(path.read_bytes()).hexdigest()



def read_csv(path):
    with path.open("r", newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def write_csv(path, names, rows):
    with path.open("w",newline="",encoding="utf-8") as stream:
        writer=csv.DictWriter(stream,fieldnames=names)
        writer.writeheader()
        writer.writerows(rows)


def tiny_geotiff(path, values, role, *, epsg=3067, nodata=None, float64=False):
    """Stdlib sparse tiled GeoTIFF: 6000x6000 metadata, only TWO data tiles.

    No full-grid allocation. DEFLATE tiles are 256x256, one Float64/UInt16/Int32
    band, EPSG geokeys and explicit NoData. Tests later open it with GDAL CLI.
    """
    nd=(nodata or NODATA[role])
    missing=float('nan') if nd['kind']=='NAN' else nd['value']
    fmt,bits,sample={'pointer':('d',64,3),'water_class':('H',16,1),'lake_id':('i',32,2)}[role]
    if float64:fmt,bits,sample='d',64,3
    tile_payloads={}
    for tile_col in (12,13):
        tile=[missing]*(256*256)
        for r,row in enumerate(values):
            for c,value in enumerate(row):
                gr,gc=3844+r,3293+c
                if gc//256 != tile_col:
                    continue
                v=missing if s.absent(value) else value
                tile[(gr%256)*256+gc%256]=float(v) if fmt=='d' else int(v)
        tile_payloads[15*24+tile_col]=zlib.compress(struct.pack('<'+fmt*len(tile),*tile))
    offsets=[0]*576
    counts=[0]*576
    nd_text=('nan' if nd['kind']=='NAN' else str(missing))+'\0'
    tags={256:(4,1,struct.pack('<I',6000)),257:(4,1,struct.pack('<I',6000)),
          258:(3,1,struct.pack('<H',bits)),259:(3,1,struct.pack('<H',8)),
          262:(3,1,struct.pack('<H',1)),277:(3,1,struct.pack('<H',1)),
          284:(3,1,struct.pack('<H',1)),322:(4,1,struct.pack('<I',256)),323:(4,1,struct.pack('<I',256)),
          324:(4,576,b'\0'*(576*4)),325:(4,576,b'\0'*(576*4)),339:(3,1,struct.pack('<H',sample)),
          33550:(12,3,struct.pack('<3d',2,2,0)),
          33922:(12,6,struct.pack('<6d',0,0,0,199000,6911000,0)),
          34735:(3,20,struct.pack('<20H',1,1,0,4,1024,0,1,1,1025,0,1,1,3072,0,1,epsg,3076,0,1,9001)),
          42113:(2,len(nd_text),nd_text.encode('ascii'))}
    def layout(tags):
        start=8+2+12*len(tags)+4
        extra=bytearray()
        entries=[]
        for tag,(kind,count,payload) in sorted(tags.items()):
            if len(payload)<=4:
                value=payload.ljust(4,b'\0')
            else:
                while (start+len(extra))%8:extra.append(0)
                value=struct.pack('<I',start+len(extra))
                extra.extend(payload)
            entries.append(struct.pack('<HHI',tag,kind,count)+value)
        return b'II*\0'+struct.pack('<I',8)+struct.pack('<H',len(tags))+b''.join(entries)+b'\0'*4+extra
    base=layout(tags)
    cursor=len(base)
    for index,payload in sorted(tile_payloads.items()):
        offsets[index]=cursor
        counts[index]=len(payload)
        cursor+=len(payload)
    tags[324]=(4,576,struct.pack('<576I',*offsets))
    tags[325]=(4,576,struct.pack('<576I',*counts))
    path.write_bytes(layout(tags)+b''.join(v for _,v in sorted(tile_payloads.items())))
    assert path.stat().st_size<65536, 'fixture must remain tiny'


def make_fixture(root, real=False):
    data,neighbors=fixtures.six_fixture(with_neighbors=True)
    paths={name:root/filename for name,filename in dict(qa='grid-qa.csv',manifest='original-inputs.csv',
           provenance='synthetic-02f-producer.json',routes='all-route-summaries.csv',neighbors='all-water-neighbors.csv',
           pointer='explicit-pointer.tif',water_class='explicit-classes.tif',lake_id='explicit-lakes.tif').items()}
    for role in a.ROLES:
        if real:tiny_geotiff(paths[role],getattr(data,role),role)
        else:paths[role].write_bytes(b'X')
    write_csv(paths['qa'],('item','value'),[dict(item=k,value=v) for k,v in
              dict(dem_cols=6000,dem_rows=6000,dem_res_x=2,dem_res_y=2,xmin=199000,xmax=211000,ymin=6899000,ymax=6911000).items()])
    write_csv(paths['manifest'],('key','value'),[dict(key=k,value=v) for k,v in
              dict(pointer_scheme='whitebox',test_id='E200000_N6900000',cell_size_m='2',
                   water_class_raster=paths['water_class'],lake_id_raster=paths['lake_id']).items()])
    records=[asdict(r) for r in s.LOCKED_SUMMARIES]
    records.append(dict(route_id=91,start_receiver_cell=123,origin_lake_objectid=123,
                        terminal_cell=123,terminal_water_class=None,terminal_lake_objectid=None,
                        route_steps=0,route_status='D8_ZERO_INTERIOR'))
    write_csv(paths['routes'],tuple(f.name for f in fields(s.Summary)),records)
    neighbor_rows=[dict(component_id=n.component_id,source_cell=n.source_cell,water_cell=n.water_cell,
                        water_class=n.water_class,lake_objectid=n.lake_id,water_z_m=1) for n in neighbors]
    neighbor_rows.append(dict(component_id=999,source_cell=6001,water_cell=6002,water_class=2,lake_objectid=None,water_z_m=1))
    write_csv(paths['neighbors'],tuple(neighbor_rows[0]),neighbor_rows)
    proof=dict(schema_version='s2b.synthetic.v1',evidence_kind='SYNTHETIC',producer_commit='a'*40,
               pointer_scheme='WHITEBOX_D8',esri_pntr=False,
               files={name:dict(path=str(paths[name]),sha256=digest(paths[name])) for name in ('qa','manifest','routes','neighbors')},
               rasters={role:dict(path=str(paths[role]),size_bytes=paths[role].stat().st_size,dtype=DTYPES[role],
                                 nodata=NODATA[role].copy(),lineage_id='synthetic-'+role,sha256_claim=digest(paths[role]))
                        for role in a.ROLES})
    paths['provenance'].write_text(json.dumps(proof),encoding='utf-8')
    request=a.Request(str(root),**{k:str(v) for k,v in paths.items()},provenance_sha256=digest(paths['provenance']))
    return request,data,proof


def metadata(role, proof):
    b=proof['rasters'][role]
    nd=b['nodata']
    return dict(driverShortName='GTiff',size=[6000,6000],geoTransform=[199000,2,0,6911000,0,-2],
                coordinateSystem=dict(wkt='PROJCRS["Synthetic",ID["EPSG",3067]]',dataAxisToSRSAxisMapping=[1,2]),
                cornerCoordinates=dict(upperLeft=[199000,6911000],lowerRight=[211000,6899000],center=[205000,6905000]),
                bands=[dict(band=1,type=b['dtype'],noDataValue='NaN' if nd['kind']=='NAN' else nd['value'])])


def xyz(values, nodata):
    lines=[]
    for row,data in enumerate(values):
        for col,value in enumerate(data):
            x,y=s.center(s.cell_id(3844+row,3293+col))
            token=('nan' if nodata['kind']=='NAN' else str(nodata['value'])) if s.absent(value) else str(value)
            lines.append(f'{x} {y} {token}')
    return ('\n'.join(lines)+'\n').encode('ascii')


def ascii_grid(values, nodata):
    missing='nan' if nodata['kind']=='NAN' else str(nodata['value'])
    header=f'ncols 52\nnrows 73\nxllcorner 205586\nyllcorner 6903166\ncellsize 2\nNODATA_value {missing}\n'
    body='\n'.join(' '.join(missing if s.absent(value) else str(value) for value in row) for row in values)
    return (header+body+'\n').encode('ascii')


class Backend:
    def __init__(self, request, data, proof):
        self.request,self.data,self.proof=request,data,proof
        self.calls=[]
        self.mutate_info=None
        self.mutate_xyz=None
        self.version=b'GDAL 3.12.2 "Chicoutimi", released 2026/02/03\n'

    def run(self, runner, args, limit=a.STDOUT_LIMIT, remaining=60):
        self.calls.append(args)
        runner.calls+=1
        if args[-1]=='--version':return self.version
        role=next(role for role in a.ROLES if getattr(self.request,role) in args)
        if '-json' in args:
            m=metadata(role,self.proof)
            if self.mutate_info:self.mutate_info(m,role)
            output=json.dumps(m).encode()
        else:
            output=ascii_grid(getattr(self.data,role),self.proof['rasters'][role]['nodata'])
            if self.mutate_xyz:output=self.mutate_xyz(output,role)
        if len(output)>limit:raise a.Stop('PROCESS_OUTPUT_SIZE_LIMIT')
        runner.bytes_read+=len(output)
        return output

    @contextmanager
    def installed(self):
        with patch.object(a.Runner,'run',autospec=True,side_effect=self.run):yield


class FixtureCase(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='mm-s2b-synthetic-')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.request,self.data,self.proof=make_fixture(self.root)
        self.backend=Backend(self.request,self.data,self.proof)

    def rewrite_proof(self):
        Path(self.request.provenance).write_text(json.dumps(self.proof),encoding='utf-8')
        self.request=replace(self.request,provenance_sha256=digest(Path(self.request.provenance)))
        self.backend.request=self.request

    def rebind_file(self,name):
        self.proof['files'][name]['sha256']=digest(Path(getattr(self.request,name)))
        self.rewrite_proof()

    def run_mocked(self):
        with self.backend.installed():return a.preflight(self.request)

    def fails(self,error):
        result=self.run_mocked()
        self.assertEqual(result.report.diagnostic_result,'FAIL',a.compact_json(result.report))
        self.assertIn(error,result.report.error)
        self.assertFalse(result.report.routing_authorized)
        return result


class PipelineTests(FixtureCase):
    def test_three_exact_windows_and_actual_csv_rows_reach_s2a(self):
        with patch.object(s,'trace',wraps=s.trace) as replay:
            result=self.run_mocked()
        self.assertEqual(result.report.diagnostic_result,'PASS',result.report.error)
        self.assertEqual(result.report.values_returned,11388)
        self.assertEqual(result.report.window,(3293,3844,52,73))
        self.assertEqual(replay.call_count,6)
        self.assertEqual(tuple(t.summary() for t in result.traces),s.LOCKED_SUMMARIES)
        self.assertEqual(result.data.provenance.summary_sha256,digest(Path(self.request.routes)))
        self.assertNotEqual(result.data.provenance.summary_sha256,s.SUMMARY_SHA256)
        self.assertEqual(dict(result.report.stages),dict.fromkeys(a.STAGES,'PASS'))
        self.assertEqual(len(self.backend.calls),8)
        extracts=[x for x in self.backend.calls if '-srcwin' in x]
        self.assertEqual(extracts,[a.window_args(a.Tools(),getattr(self.request,r)) for r in a.ROLES])

    def test_report_contains_versions_without_source_authentication(self):
        r=self.run_mocked().report
        report=json.loads(a.compact_json(r))
        self.assertEqual(len(report['csv_versions']),5)
        self.assertEqual(len(report['sources']),3)
        self.assertEqual(report['SOURCE_AUTHENTICATION'],'NOT_ASSESSED')
        self.assertEqual(report['SOURCE_PROVENANCE'],'NOT_ASSESSED')
        self.assertTrue(all(x['actual_raster_sha256']=='NOT_CHECKED' for x in report['sources']))
        self.assertEqual(report['real_raster_parity'],'NOT_ASSESSED')

    def test_scientific_locks_and_immutability(self):
        r=self.run_mocked().report
        self.assertFalse(r.routing_authorized)
        self.assertEqual((r.NATIONAL,r.MODERATE,r.hydrological_validation,r.channel_interpretation),
                         ('LOCKED','REVIEW_REQUIRED','NOT_ASSESSED','NOT_ASSESSED'))
        self.assertEqual(r.outlet_selection,'UNASSIGNED')
        with self.assertRaises(FrozenInstanceError):r.NATIONAL='OPEN'
        with self.assertRaises(ValueError):replace(r,routing_authorized=True)

    def test_no_source_bytes_names_or_timestamps_change(self):
        before={p.name:(p.read_bytes(),p.stat().st_mtime_ns) for p in self.root.iterdir()}
        self.assertEqual(self.run_mocked().report.diagnostic_result,'PASS')
        self.assertEqual(before,{p.name:(p.read_bytes(),p.stat().st_mtime_ns) for p in self.root.iterdir()})

    def test_csv_sha_change_stops_before_raster_metadata(self):
        with Path(self.request.routes).open('a') as f:f.write('\n')
        self.fails('CSV_FILE_HASH_CHANGED')
        self.assertEqual(len(self.backend.calls),2)

    def test_missing_csv_no_substitution(self):
        Path(self.request.routes).unlink()
        result=self.fails('No such file')
        self.assertEqual(self.backend.calls,[])
        self.assertEqual(dict(result.report.stages)['WINDOW_READ'],'NOT_RUN')

    def test_changed_selected_steps_even_with_updated_hash_stop(self):
        rows=read_csv(Path(self.request.routes))
        rows[0]['route_steps']='20'
        write_csv(Path(self.request.routes),tuple(rows[0]),rows)
        self.rebind_file('routes')
        self.fails('changed/duplicate/conflicting')
        self.assertEqual(len(self.backend.calls),2)

    def test_changed_receiver_even_with_updated_hash_stop(self):
        rows=read_csv(Path(self.request.routes))
        rows[0]['start_receiver_cell']='23337319'
        write_csv(Path(self.request.routes),tuple(rows[0]),rows)
        self.rebind_file('routes')
        self.fails('changed/duplicate/conflicting')

    def test_duplicate_unselected_route_id_is_detected(self):
        rows=read_csv(Path(self.request.routes))
        rows.append(rows[-1])
        write_csv(Path(self.request.routes),tuple(rows[0]),rows)
        self.rebind_file('routes')
        self.fails('DUPLICATE_OR_INVALID_ROUTE_ID')

    def test_changed_02c_lake_stop(self):
        rows=read_csv(Path(self.request.neighbors))
        rows[0]['lake_objectid']='1894'
        write_csv(Path(self.request.neighbors),tuple(rows[0]),rows)
        self.rebind_file('neighbors')
        self.fails('02C_CHANGED_SOURCE_CLASS_OR_LAKE')

    def test_duplicate_02c_neighbor_stop(self):
        rows=read_csv(Path(self.request.neighbors))
        rows[1]=rows[0]
        write_csv(Path(self.request.neighbors),tuple(rows[0]),rows)
        self.rebind_file('neighbors')
        self.fails('02C_EXACT_THREE_NEIGHBORS')

    def test_qa_mismatch_stop(self):
        p=Path(self.request.qa)
        p.write_text(p.read_text().replace('dem_cols,6000','dem_cols,5999'))
        self.rebind_file('qa')
        self.fails('INPUT_QA_GRID')

    def test_manifest_paths_are_discovered_not_guessed(self):
        self.assertNotIn('ranta10_water_class.tif',self.request.water_class)
        self.assertEqual(self.run_mocked().report.diagnostic_result,'PASS')
        p=Path(self.request.manifest)
        p.write_text(p.read_text().replace(self.request.water_class,self.request.lake_id))
        self.rebind_file('manifest')
        self.fails('INPUT_MANIFEST_BINDING')

    def test_duplicate_manifest_keys_stop(self):
        p=Path(self.request.manifest)
        with p.open('a') as f:f.write('pointer_scheme,whitebox\n')
        self.rebind_file('manifest')
        self.fails('DUPLICATE_MANIFEST_KEY')

    def test_unbound_provenance_document_hash_stop(self):
        self.request=replace(self.request,provenance_sha256='b'*64)
        self.fails('PROVENANCE_DOCUMENT_HASH_CHANGED')

    def test_unknown_command_or_approval_fields_stop(self):
        for key in ('command','approved','output_path'):
            with self.subTest(key=key):
                self.proof[key]='anything'
                self.rewrite_proof()
                self.fails('UNKNOWN_OR_MISSING_FIELDS')
                del self.proof[key]

    def test_oversized_provenance_integer_is_rejected_as_json(self):
        p=Path(self.request.provenance)
        p.write_text('{"oversized":'+('1'*5000)+'}')
        self.request=replace(self.request,provenance_sha256=digest(p))
        self.fails('INVALID_JSON')

    def test_timeout_report_marks_resource_stage_stop(self):
        with patch.object(a.Runner,'run',side_effect=a.Stop('GDAL_TIMEOUT')):
            result=a.preflight(self.request)
        self.assertEqual(result.report.diagnostic_result,'FAIL')
        self.assertEqual(dict(result.report.stages)['RESOURCE_BOUND'],'STOP')
        self.assertEqual(result.report.values_returned,0)

    def test_duplicate_json_keys_stop(self):
        p=Path(self.request.provenance)
        text=p.read_text().replace('"esri_pntr": false','"esri_pntr": false, "esri_pntr": true')
        p.write_text(text)
        self.request=replace(self.request,provenance_sha256=digest(p))
        self.fails('DUPLICATE_JSON_KEY')

    def test_wrong_whitebox_convention_stop(self):
        self.proof['esri_pntr']=True
        self.rewrite_proof()
        self.fails('WRONG_D8_CONVENTION')

    def test_raster_size_change_stop_without_hash_scan(self):
        Path(self.request.pointer).write_bytes(b'XX')
        self.fails('RASTER_SIZE_CHANGED')

    def test_raster_hash_claim_is_never_authenticated(self):
        self.proof['rasters']['pointer']['sha256_claim']='b'*64
        self.rewrite_proof()
        result=self.run_mocked()
        self.assertEqual(result.report.diagnostic_result,'PASS')
        self.assertEqual(result.report.SOURCE_AUTHENTICATION,'NOT_ASSESSED')
        self.assertEqual(result.report.sources[0].actual_raster_sha256,'NOT_CHECKED')

    def test_missing_lineage_stop(self):
        self.proof['rasters']['pointer']['lineage_id']=''
        self.rewrite_proof()
        self.fails('nonempty bounded string')

    def test_source_replacement_during_read_stop(self):
        original=self.backend.run
        def mutate(runner,args,limit=a.STDOUT_LIMIT,remaining=60):
            raw=original(runner,args,limit,remaining)
            if '-json' in args:
                p=Path(self.request.pointer)
                p.write_bytes(b'Y')
            return raw
        with patch.object(a.Runner,'run',autospec=True,side_effect=mutate):result=a.preflight(self.request)
        self.assertIn('SOURCE_CHANGED',result.report.error)
        self.assertFalse(any('-srcwin' in args for args in self.backend.calls))

    def test_wrong_gdal_version_stops(self):
        self.backend.version=b'GDAL 3.10.3, released 2025/04/01\n'
        self.fails('GDAL_3_12_2_REQUIRED')
        self.assertEqual(len(self.backend.calls),1)

    def test_fixed_window_guard_cannot_be_expanded(self):
        with patch.object(a,'WINDOW',(3292,3844,53,73)):
            self.fails('FIXED_WINDOW_GUARD')
        self.assertEqual(self.backend.calls,[])

    def test_trace_parity_failure_keeps_six_original_identities(self):
        pointer=[list(r) for r in self.data.pointer]
        r,c=s.row_col(23343318)
        pointer[r-3844][c-3293]=0
        self.backend.data=replace(self.data,pointer=pointer)
        result=self.fails('S2A_SUMMARY_PARITY')
        self.assertEqual(tuple(t.route_id for t in result.traces),(11,14,15,16,18,20))
        self.assertEqual(dict(result.report.stages)['S2A_TRACE_PARITY'],'STOP')
        self.assertEqual(dict(result.report.stages)['WATER_NEIGHBOR_PARITY'],'NOT_RUN')

    def test_neighbor_raster_contradiction_fails(self):
        lake=[list(r) for r in self.data.lake_id]
        r,c=s.row_col(fixtures.six_fixture(True)[1][0].water_cell)
        lake[r-3844][c-3293]=999
        self.backend.data=replace(self.data,lake_id=lake)
        result=self.fails('02C_RASTER_NEIGHBOR_PARITY')
        self.assertEqual(dict(result.report.stages)['S2A_TRACE_PARITY'],'PASS')


class PathTests(FixtureCase):
    def test_real_csc_scope_is_rejected_without_file_access(self):
        with patch('os.lstat',side_effect=AssertionError('must not inspect CSC')):
            with self.assertRaises(a.Stop):replace(self.request,root='/scratch/project_2004707/pienvedet')

    def test_real_evidence_mode_is_not_authorized(self):
        with self.assertRaises(a.Stop):replace(self.request,evidence_kind='ORIGINAL')

    def test_parent_escape_relative_and_remote_paths_rejected(self):
        for p in ('../ptr.tif','/vsicurl/https://example.org/a.tif',str(self.root/'..'/'x.tif')):
            with self.subTest(path=p):
                try:bad=replace(self.request,pointer=p)
                except a.Stop:continue
                self.assertEqual(a.preflight(bad).report.diagnostic_result,'FAIL')

    def test_shared_fixture_directory_is_rejected(self):
        os.chmod(self.root,0o755)
        self.fails('PRIVATE_FIXTURE_DIRECTORY_REQUIRED')

    def test_symlink_source_stop(self):
        p=Path(self.request.pointer)
        real=self.root/'other.tif'
        p.rename(real)
        p.symlink_to(real)
        self.fails('SYMLINK_SOURCE_OR_ANCESTOR')

    def test_symlink_ancestor_stop(self):
        sub=self.root/'directory'
        sub.mkdir()
        p=sub/'ptr.tif'
        p.write_bytes(b'X')
        link=self.root/'link'
        link.symlink_to(sub,target_is_directory=True)
        self.request=replace(self.request,pointer=str(link/'ptr.tif'))
        self.fails('SYMLINK_SOURCE_OR_ANCESTOR')

    def test_hardlinked_source_stop(self):
        os.link(self.request.pointer,self.root/'hardlink.tif')
        self.fails('SOURCE_NOT_PRIVATE_REGULAR_FILE')

    def test_output_path_and_custom_window_are_not_api_options(self):
        with self.assertRaises(TypeError):a.preflight(self.request,output_path=str(self.root/'new.tif'))
        with self.assertRaises(TypeError):replace(self.request,width=6000)
        self.assertEqual(a.window_args(a.Tools(),self.request.pointer)[-1],'/vsistdout/')
        for tool in ('gdalinfo','/bin/sh','/usr/bin/gdalinfo\0','/usr/bin/../gdalinfo'):
            with self.subTest(tool=tool),self.assertRaises(a.Stop):a.Tools(info=tool)

    def test_oversized_csv_stop(self):
        Path(self.request.routes).write_bytes(b'x'*(a.SMALL_FILE_LIMIT+1))
        self.fails('SMALL_FILE_SIZE_LIMIT')

    def test_csv_duplicate_headers_and_bad_width_stop(self):
        for raw in (b'a,a\n1,2\n',b'a,b\n1,2,3\n',b'a,b\n1\n'):
            with self.subTest(raw=raw),self.assertRaises(a.Stop):a.csv_rows(raw,('a',))


class MetadataTests(FixtureCase):
    def mutate_and_fail(self,callback,error):
        self.backend.mutate_info=callback
        result=self.fails(error)
        self.assertFalse(any('-srcwin' in args for args in self.backend.calls))
        return result

    def test_malformed_metadata_structures_stop(self):
        for raw in (b'[]',b'null',b'{"size":[6000,6000]}'):
            with self.subTest(raw=raw),self.assertRaises(a.Stop):
                a.verify_metadata(raw,self.proof['rasters']['pointer'],'pointer')

    def test_wrong_crs(self):
        self.mutate_and_fail(lambda m,r:m['coordinateSystem'].update(wkt='PROJCRS["x",ID["EPSG",4326]]'),'RASTER_CRS')

    def test_wrong_axis_mapping(self):
        self.mutate_and_fail(lambda m,r:m['coordinateSystem'].update(dataAxisToSRSAxisMapping=[2,1]),'RASTER_CRS')

    def test_wrong_origin_resolution_rotation(self):
        for transform in ([199002,2,0,6911000,0,-2],[199000,1,0,6911000,0,-2],[199000,2,1,6911000,0,-2]):
            with self.subTest(transform=transform):
                self.backend.mutate_info=lambda m,r:m.update(geoTransform=transform)
                self.fails('RASTER_AFFINE_OR_ORIGIN')

    def test_wrong_dimensions(self):
        self.mutate_and_fail(lambda m,r:m.update(size=[6000,5999]),'RASTER_DRIVER_OR_DIMENSIONS')

    def test_wrong_driver_vrt_is_not_accepted(self):
        self.mutate_and_fail(lambda m,r:m.update(driverShortName='VRT'),'RASTER_DRIVER_OR_DIMENSIONS')

    def test_mismatched_extent_center(self):
        self.mutate_and_fail(lambda m,r:m['cornerCoordinates'].update(center=[0,0]),'RASTER_EXTENT_OR_CENTER')

    def test_extra_band(self):
        self.mutate_and_fail(lambda m,r:m['bands'].append(m['bands'][0].copy()),'RASTER_BAND_COUNT')

    def test_wrong_dtype(self):
        self.mutate_and_fail(lambda m,r:m['bands'][0].update(type='CFloat64'),'RASTER_DTYPE')

    def test_altered_nodata(self):
        self.mutate_and_fail(lambda m,r:m['bands'][0].update(noDataValue=-9998),'NODATA_MISMATCH')

    def test_zero_cannot_be_pointer_nodata(self):
        self.proof['rasters']['pointer']['nodata']={'kind':'FINITE','value':0}
        self.rewrite_proof()
        self.mutate_and_fail(lambda m,r:None,'ZERO_POINTER_CANNOT_BE_NODATA')

    def test_valid_water_class_cannot_be_nodata(self):
        self.proof['rasters']['water_class']['nodata']={'kind':'FINITE','value':1}
        self.rewrite_proof()
        self.fails('WATER_CLASS_CANNOT_BE_NODATA')

    def test_positive_lake_id_cannot_be_nodata(self):
        self.proof['rasters']['lake_id']['nodata']={'kind':'FINITE','value':1892}
        self.rewrite_proof()
        self.fails('POSITIVE_LAKE_ID_CANNOT_BE_NODATA')

    def test_no_scale_offset_overview_or_mask(self):
        for key,value in (('scale',2),('offset',1),('overviews',[{}]),('mask',{'flags':['PER_DATASET']})):
            with self.subTest(key=key):
                self.backend.mutate_info=lambda m,r:m['bands'][0].update({key:value})
                self.fails('MASK_UNSUPPORTED' if key=='mask' else 'SCALE_OFFSET_OR_OVERVIEW_UNSUPPORTED')

    def test_missing_nodata_is_not_inferred(self):
        self.mutate_and_fail(lambda m,r:m['bands'][0].pop('noDataValue'),'NODATA_MISMATCH')


class XYZTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data,_=fixtures.six_fixture(True)
        cls.raw=xyz(cls.data.pointer,NODATA['pointer'])

    def test_exact_row_major_shape_and_zero_preserved(self):
        result=a.parse_xyz(self.raw,NODATA['pointer'],'pointer')
        self.assertEqual((len(result),len(result[0])),(73,52))
        self.assertEqual(result[0][0],0)
        self.assertFalse(s.absent(result[0][0]))

    def test_typed_nodata_maps_to_null_without_recoding_other_values(self):
        raw=self.raw.replace(b' 0\n',b' -9999\n',1)
        result=a.parse_xyz(raw,NODATA['pointer'],'pointer')
        self.assertEqual(result[0][0],s.Missing.NULL)
        self.assertEqual(result[0][1],0)

    def test_large_float_nodata_is_normalized_before_finite_data_range_check(self):
        raw=self.raw.replace(b' 0\n',b' -1.7976931348623157e308\n',1)
        nd={'kind':'FINITE','value':-1.7976931348623157e308}
        self.assertEqual(a.parse_xyz(raw,nd,'pointer')[0][0],s.Missing.NULL)
        self.assertEqual(a.parse_xyz(raw,nd,'pointer')[0][1],0)
        with self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['pointer'],'pointer')

    def test_nan_maps_only_with_declared_nan_nodata(self):
        raw=self.raw.replace(b' 0\n',b' nan\n',1)
        self.assertEqual(a.parse_xyz(raw,{'kind':'NAN'},'pointer')[0][0],s.Missing.NAN)
        with self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['pointer'],'pointer')

    def test_malformed_xyz_three_fields(self):
        raw=self.raw.replace(b'205587 6903311 0',b'205587 6903311 0 99',1)
        with self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['pointer'],'pointer')

    def test_duplicate_reordered_or_misaligned_centers(self):
        lines=self.raw.splitlines()
        for variant in ([lines[1],lines[0]]+lines[2:],[lines[0]]+lines[:-1],
                        [lines[0].replace(b'205587',b'205588')]+lines[1:]):
            with self.subTest(first=variant[0]),self.assertRaises(a.Stop):
                a.parse_xyz(b'\n'.join(variant),NODATA['pointer'],'pointer')

    def test_missing_or_extra_cells(self):
        for raw in (self.raw+self.raw.splitlines()[0]+b'\n',self.raw.split(b'\n',1)[1]):
            with self.subTest(length=len(raw)),self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['pointer'],'pointer')

    def test_subprecision_coordinate_change_is_not_rounded_away(self):
        raw=self.raw.replace(b'205587',b'205587.000000000000000001',1)
        with self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['pointer'],'pointer')

    def test_fractional_pointer_or_underflow_cannot_become_zero(self):
        for value in (b'1e-999',b'2.0000000000000000001'):
            with self.subTest(value=value),self.assertRaises(a.Stop):
                a.parse_xyz(self.raw.replace(b' 0\n',b' '+value+b'\n',1),NODATA['pointer'],'pointer')

    def test_nonfinite_and_unparseable_values(self):
        for token in (b'inf',b'1e999',b'text',b'1.#IND',b'0x2'):
            with self.subTest(token=token),self.assertRaises(a.Stop):
                a.parse_xyz(self.raw.replace(b' 0\n',b' '+token+b'\n',1),NODATA['pointer'],'pointer')

    def test_non_ascii_and_oversized_output(self):
        for raw in (b'\xff',b'X'*(a.STDOUT_LIMIT+1)):
            with self.subTest(length=len(raw)),self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['pointer'],'pointer')

    def test_zero_water_class_not_silently_converted_to_land(self):
        with self.assertRaises(a.Stop):a.parse_xyz(self.raw,NODATA['water_class'],'water_class')

    def test_lake_ids_must_be_exact_positive_integers(self):
        for token in (b'1892.5',b'0',b'-1',b'2147483648'):
            raw=self.raw.replace(b' 0\n',b' '+token+b'\n',1)
            with self.subTest(token=token),self.assertRaises(a.Stop):a.parse_xyz(raw,NODATA['lake_id'],'lake_id')


class ASCIITransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data,_=fixtures.six_fixture(True)
        cls.raw=ascii_grid(cls.data.pointer,NODATA['pointer'])

    def test_fixed_ascii_header_and_shape(self):
        self.assertEqual(a.parse_ascii(self.raw,NODATA['pointer'],'pointer'),self.data.pointer)

    def test_malformed_xyz_is_not_an_ascii_grid_fallback(self):
        with self.assertRaises(a.Stop):a.parse_ascii(xyz(self.data.pointer,NODATA['pointer']),NODATA['pointer'],'pointer')

    def test_wrong_ascii_window_header_or_pixel_size_stop(self):
        for old,new in ((b'ncols 52',b'ncols 53'),(b'yllcorner 6903166',b'yllcorner 6903167'),
                        (b'cellsize 2',b'cellsize 1'),(b'xllcorner 205586',b'xllcorner 205586.00000000000001')):
            with self.subTest(old=old),self.assertRaises(a.Stop):
                a.parse_ascii(self.raw.replace(old,new,1),NODATA['pointer'],'pointer')

    def test_wrong_ascii_nodata_or_duplicate_header_stop(self):
        for raw in (self.raw.replace(b'NODATA_value -9999',b'NODATA_value -9998',1),
                    self.raw.replace(b'nrows 73',b'ncols 52',1)):
            with self.subTest(raw=raw[:100]),self.assertRaises(a.Stop):
                a.parse_ascii(raw,NODATA['pointer'],'pointer')

    def test_wrong_ascii_row_count_or_width_stop(self):
        for raw in (self.raw+self.raw.splitlines()[-1]+b'\n',self.raw.split(b'\n',1)[1],
                    self.raw.replace(b'0 0 ',b'0 ',1)):
            with self.subTest(length=len(raw)),self.assertRaises(a.Stop):
                a.parse_ascii(raw,NODATA['pointer'],'pointer')

    def test_float64_fractional_pointer_survives_transport_parser(self):
        raw=self.raw.replace(b'0 ',b'2.00000001 ',1)
        self.assertEqual(a.parse_ascii(raw,NODATA['pointer'],'pointer')[0][0],2.00000001)



class RunnerTests(unittest.TestCase):
    def write_process(self,stdout=b'abc',stderr=b'',code=0):
        def fake(args,**kwargs):
            self.assertIs(kwargs['shell'],False)
            self.assertLessEqual(kwargs['timeout'],10)
            self.assertIsInstance(args,tuple)
            self.assertNotIn('capture_output',kwargs)
            self.assertEqual(kwargs['env']['GDAL_PAM_ENABLED'],'NO')
            self.assertEqual(kwargs['env']['PROJ_NETWORK'],'OFF')
            if stdout:os.write(kwargs['stdout'],stdout)
            if stderr:os.write(kwargs['stderr'],stderr)
            return subprocess.CompletedProcess(args,code)
        return fake

    def test_safe_run_argument_array_and_capped_capture(self):
        with patch.object(a.subprocess,'run',side_effect=self.write_process()) as proc:
            r=a.Runner()
            self.assertEqual(r.run(('/usr/bin/gdalinfo','--version')),b'abc')
            self.assertEqual((r.bytes_read,r.calls),(3,1))
            self.assertEqual(proc.call_count,1)

    def test_stdout_limit_enforced_during_collection(self):
        with patch.object(a.subprocess,'run',side_effect=self.write_process(stdout=b'x'*1025)):
            with self.assertRaisesRegex(a.Stop,'OUTPUT_SIZE_LIMIT'):
                a.Runner().run(('/usr/bin/gdalinfo','--version'),limit=1024)

    def test_stderr_limit_enforced(self):
        with patch.object(a.subprocess,'run',side_effect=self.write_process(stderr=b'x'*(a.STDERR_LIMIT+1))):
            with self.assertRaisesRegex(a.Stop,'OUTPUT_SIZE_LIMIT'):
                a.Runner().run(('/usr/bin/gdalinfo','--version'))

    def test_timeout_without_retry(self):
        with patch.object(a.subprocess,'run',side_effect=subprocess.TimeoutExpired('gdal',10)) as proc:
            with self.assertRaisesRegex(a.Stop,'GDAL_TIMEOUT'):a.Runner().run(('/usr/bin/gdalinfo','--version'))
            self.assertEqual(proc.call_count,1)

    def test_driver_failure_has_no_fallback_or_output_file(self):
        with patch.object(a.subprocess,'run',side_effect=self.write_process(code=1)) as proc:
            with self.assertRaisesRegex(a.Stop,'NO_FALLBACK'):a.Runner().run(('/usr/bin/gdal_translate','x'))
            self.assertEqual(proc.call_count,1)

    def test_warnings_require_review(self):
        with patch.object(a.subprocess,'run',side_effect=self.write_process(stderr=b'Warning')):
            with self.assertRaisesRegex(a.Stop,'WARNING'):a.Runner().run(('/usr/bin/gdalinfo','x'))

    def test_total_timeout_and_command_budget(self):
        with self.assertRaisesRegex(a.Stop,'TOTAL_TIMEOUT'):a.Runner().run(('/usr/bin/gdalinfo','x'),remaining=0)
        r=a.Runner()
        r.calls=8
        with patch.object(a.subprocess,'run') as proc:
            with self.assertRaisesRegex(a.Stop,'COMMAND_BUDGET'):r.run(('/usr/bin/gdalinfo','x'))
            proc.assert_not_called()

    def test_bounds_cannot_be_relaxed(self):
        for timeout in (0,11,True):
            with self.subTest(timeout=timeout),self.assertRaises(a.Stop):a.Runner(timeout)
        with self.assertRaises(a.Stop):a.Runner().run(('/usr/bin/gdalinfo',),limit=a.STDOUT_LIMIT+1)
        with self.assertRaises(a.Stop):a.Runner().run('gdalinfo --version')

    def test_actual_bounded_pipe_with_small_local_process(self):
        raw=a.Runner().run((sys.executable,'-c','import sys; sys.stdout.write("synthetic pipe")'))
        self.assertEqual(raw,b'synthetic pipe')

    def test_actual_excess_output_is_bounded(self):
        with self.assertRaisesRegex(a.Stop,'OUTPUT_SIZE_LIMIT'):
            a.Runner().run((sys.executable,'-c','import os; os.write(1,b"x"*100000)'),limit=1024)


GDAL_EXACT=False
if os.environ.get('MM_S2B_GDAL_TESTS')=='1' and shutil.which('gdalinfo') and shutil.which('gdal_translate'):
    found=subprocess.run(['gdalinfo','--version'],capture_output=True,text=True,timeout=5)
    GDAL_EXACT=bool(a.re.match(r'^GDAL 3\.12\.2(?:[ ,]|$)',found.stdout))


@unittest.skipUnless(GDAL_EXACT,'NOT_RUN: enable MM_S2B_GDAL_TESTS=1 in GDAL 3.12.2 CLI environment')
class ActualGDALFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='mm-s2b-synthetic-')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.request,self.data,self.proof=make_fixture(self.root,real=True)
        self.tools=a.Tools(shutil.which('gdalinfo'),shutil.which('gdal_translate'))

    def rebind_raster(self,role):
        p=Path(getattr(self.request,role))
        self.proof['rasters'][role]['size_bytes']=p.stat().st_size
        self.proof['rasters'][role]['sha256_claim']=digest(p)
        Path(self.request.provenance).write_text(json.dumps(self.proof))
        self.request=replace(self.request,provenance_sha256=digest(Path(self.request.provenance)))

    def test_real_ascii_stdout_driver_and_full_synthetic_chain_parity(self):
        before={p.name:(digest(p),p.stat().st_mtime_ns) for p in self.root.iterdir()}
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'PASS',a.compact_json(result.report))
        self.assertEqual(result.report.values_returned,11388)
        self.assertTrue(all(v=='PASS' for _,v in result.report.stages))
        self.assertEqual(tuple(t.summary() for t in result.traces),s.LOCKED_SUMMARIES)
        self.assertEqual(result.data.pointer,self.data.pointer)
        self.assertEqual(result.data.water_class,self.data.water_class)
        self.assertEqual(result.data.lake_id,self.data.lake_id)
        self.assertEqual(before,{p.name:(digest(p),p.stat().st_mtime_ns) for p in self.root.iterdir()})
        self.assertTrue(all(Path(getattr(self.request,r)).stat().st_size<65536 for r in a.ROLES))

    def test_real_wrong_crs_stops_before_window_reads(self):
        tiny_geotiff(Path(self.request.pointer),self.data.pointer,'pointer',epsg=3857)
        self.rebind_raster('pointer')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'FAIL')
        self.assertIn('RASTER_CRS',result.report.error)
        self.assertEqual(result.report.values_returned,0)

    def test_real_nan_nodata_is_explicit_and_zero_is_still_zero(self):
        self.proof['rasters']['pointer']['nodata']={'kind':'NAN'}
        # Put one NaN outside the six observed chains, but inside the fixed window.
        values=[list(r) for r in self.data.pointer]
        values[0][0]=s.Missing.NAN
        tiny_geotiff(Path(self.request.pointer),values,'pointer',nodata={'kind':'NAN'})
        self.rebind_raster('pointer')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'PASS',a.compact_json(result.report))
        self.assertEqual(result.data.pointer[0][0],s.Missing.NAN)
        self.assertEqual(result.data.pointer[0][1],0)

    def test_real_float64_pointer_is_not_rounded_to_valid_d8(self):
        values=[list(r) for r in self.data.pointer]
        row,col=s.row_col(23343318)
        values[row-3844][col-3293]=128.00000001
        tiny_geotiff(Path(self.request.pointer),values,'pointer')
        self.rebind_raster('pointer')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'FAIL')
        self.assertEqual(result.traces[1].route_status,'D8_POINTER_INVALID')
        self.assertEqual(result.data.pointer[row-3844][col-3293],128.00000001)

    def test_real_float64_lake_id_above_float32_exact_range_is_preserved(self):
        lakes=[list(r) for r in self.data.lake_id]
        water=[list(r) for r in self.data.water_class]
        lakes[0][0]=16777217
        water[0][0]=1
        tiny_geotiff(Path(self.request.lake_id),lakes,'lake_id',float64=True)
        tiny_geotiff(Path(self.request.water_class),water,'water_class')
        self.proof['rasters']['lake_id']['dtype']='Float64'
        self.rebind_raster('lake_id')
        self.rebind_raster('water_class')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'PASS',a.compact_json(result.report))
        self.assertEqual(result.data.lake_id[0][0],16777217)
        self.assertNotEqual(result.data.lake_id[0][0],16777216)

    def test_real_large_float64_nodata_survives_gdal_text_formatting(self):
        nd={'kind':'FINITE','value':-1.7976931348623157e308}
        self.proof['rasters']['pointer']['nodata']=nd
        values=[list(r) for r in self.data.pointer]
        values[0][0]=s.Missing.NULL
        tiny_geotiff(Path(self.request.pointer),values,'pointer',nodata=nd)
        self.rebind_raster('pointer')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'PASS',a.compact_json(result.report))
        self.assertEqual(result.data.pointer[0][0],s.Missing.NULL)
        self.assertEqual(result.data.pointer[0][1],0)

    def test_real_typed_nodata_and_invalid_pointer_fail_without_reclassification(self):
        values=[list(r) for r in self.data.pointer]
        row,col=s.row_col(23343318)
        values[row-3844][col-3293]=s.Missing.NULL
        tiny_geotiff(Path(self.request.pointer),values,'pointer')
        self.rebind_raster('pointer')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'FAIL')
        self.assertEqual(result.traces[1].route_status,'D8_POINTER_NA')
        self.assertEqual(result.data.pointer[0][0],0)
        values[row-3844][col-3293]=3
        tiny_geotiff(Path(self.request.pointer),values,'pointer')
        self.rebind_raster('pointer')
        result=a.preflight(self.request,self.tools)
        self.assertEqual(result.report.diagnostic_result,'FAIL')
        self.assertEqual(result.traces[1].route_status,'D8_POINTER_INVALID')


if __name__=='__main__':unittest.main()
