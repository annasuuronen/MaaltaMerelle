"""S2A: bounded, immutable in-memory replay; no raster adapter or authorization.

Public entry point: audit_low(window, original_summaries, neighbors_02c=None).
trace() is the bounded mechanics helper for synthetic edge/censoring tests.
Only Python standard-library functions over supplied values are used.
"""
from dataclasses import dataclass, field, fields, is_dataclass
from enum import Enum
from hashlib import sha256
import json
import math
import re


class Stop(ValueError):
    """Invalid input/unsupported claim: no successful audit is returned."""


class Missing(Enum):
    NULL = "EXPLICIT_NULL"
    NAN = "EXPLICIT_NAN"


OFFSETS = ((1, -1, 1), (2, 0, 1), (4, 1, 1), (8, 1, 0),
           (16, 1, -1), (32, 0, -1), (64, -1, -1), (128, -1, 0))
SUMMARY_SHA256 = "402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5"
TERMINAL = 23211319
MAX_TRANSITIONS = 24
MAX_INSPECTIONS = 25
MAX_LAKE_ID = 2147483647  # 02F stores lake identifiers as R integers.


def integer(value, name, lo=1, hi=36000000):
    if type(value) is not int or not lo <= value <= hi:
        raise Stop(f"{name}: exact integer required in [{lo}, {hi}]")
    return value


def text_id(value, name):
    if type(value) is not str or not value.strip() or len(value) > 256:
        raise Stop(f"{name}: nonempty bounded string required")
    return value


def numeric(value, name):
    if isinstance(value, Missing):
        return value
    if value is None:
        return Missing.NULL
    if type(value) not in (int, float):
        raise Stop(f"{name}: number or explicit null/NaN required")
    if type(value) is float and math.isnan(value):
        return Missing.NAN
    if abs(value) > 2**53 or not math.isfinite(value):
        raise Stop(f"{name}: finite exactly representable numeric magnitude required")
    return value


def absent(value):
    return isinstance(value, Missing)


@dataclass(frozen=True)
class Grid:
    grid_id: str = "LOW-E200000-N6900000"
    nrow: int = 6000
    ncol: int = 6000
    epsg: int = 3067
    resolution_m: int = 2
    xmin: int = 199000
    xmax: int = 211000
    ymin: int = 6899000
    ymax: int = 6911000

    def __post_init__(self):
        expected = ("LOW-E200000-N6900000", 6000, 6000, 3067, 2,
                    199000, 211000, 6899000, 6911000)
        actual = tuple(getattr(self, f.name) for f in fields(self))
        if actual != expected or any(type(v) is not int for v in actual[1:]):
            raise Stop("wrong LOW grid/CRS/origin/resolution")


@dataclass(frozen=True)
class Window:
    xoff: int = 3293
    yoff: int = 3844
    width: int = 52
    height: int = 73

    def __post_init__(self):
        integer(self.xoff, "xoff", 0, 5999)
        integer(self.yoff, "yoff", 0, 5999)
        integer(self.width, "width", 1, 52)
        integer(self.height, "height", 1, 73)
        if self.xoff + self.width > 6000 or self.yoff + self.height > 6000:
            raise Stop("window outside full LOW grid")

    def contains(self, row, col):
        return (self.yoff <= row < self.yoff + self.height and
                self.xoff <= col < self.xoff + self.width)


def cell_id(row, col):
    integer(row, "row0", 0, 5999)
    integer(col, "col0", 0, 5999)
    return row * 6000 + col + 1


def row_col(cell):
    integer(cell, "cell_id")
    return divmod(cell - 1, 6000)


def center(cell):
    row, col = row_col(cell)
    return (199000 + 2 * col + 1, 6911000 - 2 * row - 1)


@dataclass(frozen=True)
class Provenance:
    """Declared labels only. No path access or claim of file authentication."""
    data_kind: str
    pointer_id: str
    water_class_id: str
    lake_id_id: str
    evidence_version: str
    producer_commit: str
    summary_sha256: str
    nodata_policy: str = "EXPLICIT_NULL_OR_NAN"
    source_identity_verified: bool = field(default=False, init=False)

    def __post_init__(self):
        if self.data_kind not in ("SYNTHETIC", "UNVERIFIED_IN_MEMORY"):
            raise Stop("real-source authentication is outside S2A")
        for name in ("pointer_id", "water_class_id", "lake_id_id", "evidence_version"):
            text_id(getattr(self, name), name)
        if len({self.pointer_id, self.water_class_id, self.lake_id_id}) != 3:
            raise Stop("three distinct source identities required")
        if type(self.producer_commit) is not str or not re.fullmatch(r"[0-9a-f]{40}", self.producer_commit):
            raise Stop("invalid producer commit")
        if type(self.summary_sha256) is not str or not re.fullmatch(r"[0-9a-f]{64}", self.summary_sha256):
            raise Stop("invalid declared 02F SHA256")
        if self.nodata_policy != "EXPLICIT_NULL_OR_NAN":
            raise Stop("explicit NoData normalization required; numeric sentinels unsupported")


def plain(value):
    """JSON-safe representation; explicit missing markers, never NaN JSON."""
    if isinstance(value, Missing):
        return value.value
    if is_dataclass(value) and type(value) in _RECORD_TYPES:
        return {f.name: plain(getattr(value, f.name)) for f in fields(value)}
    if type(value) in (tuple, list):
        return [plain(v) for v in value]
    if value is None or type(value) in (str, bool, int):
        return value
    if type(value) is float and math.isfinite(value):
        return value
    raise Stop("unsupported report value")


def canonical_json(value):
    return json.dumps(plain(value), sort_keys=True, separators=(",", ":"), allow_nan=False)


@dataclass(frozen=True)
class WindowData:
    grid: Grid
    window: Window
    provenance: Provenance
    pointer: tuple
    water_class: tuple
    lake_id: tuple
    content_sha256: str = field(init=False)

    def __post_init__(self):
        if type(self.grid) is not Grid or type(self.window) is not Window or type(self.provenance) is not Provenance:
            raise Stop("typed immutable grid/window/provenance required")
        for name in ("pointer", "water_class", "lake_id"):
            array = getattr(self, name)
            if type(array) not in (tuple, list) or len(array) != self.window.height:
                raise Stop(f"{name}: wrong row count")
            rows = []
            for row in array:
                if type(row) not in (tuple, list) or len(row) != self.window.width:
                    raise Stop(f"{name}: wrong column count")
                values = tuple(numeric(v, name) for v in row)
                if name == "lake_id" and any(not absent(v) and (v <= 0 or v > MAX_LAKE_ID or v != int(v)) for v in values):
                    raise Stop("lake IDs must be missing or exact positive integers; no truncation")
                rows.append(values)
            object.__setattr__(self, name, tuple(rows))
        # Hash supplied values AND metadata; not a hash/authentication of CSC files.
        payload = tuple(getattr(self, name) for name in
                        ("grid", "window", "provenance", "pointer", "water_class", "lake_id"))
        object.__setattr__(self, "content_sha256", sha256(canonical_json(payload).encode()).hexdigest())

    def sample(self, cell):
        row, col = row_col(cell)
        if not self.window.contains(row, col):
            raise Stop("OUTSIDE_BOUNDED_WINDOW")
        i, j = row - self.window.yoff, col - self.window.xoff
        x, y = center(cell)
        return Cell(cell, row, col, x, y, self.pointer[i][j],
                    self.water_class[i][j], self.lake_id[i][j])


@dataclass(frozen=True)
class Summary:
    route_id: int
    start_receiver_cell: int
    origin_lake_objectid: int
    terminal_cell: int
    terminal_water_class: int | None
    terminal_lake_objectid: int | None
    route_steps: int
    route_status: str

    def __post_init__(self):
        integer(self.route_id, "route_id")
        integer(self.start_receiver_cell, "start_receiver_cell")
        integer(self.origin_lake_objectid, "origin_lake_objectid", 1, MAX_LAKE_ID)
        integer(self.terminal_cell, "terminal_cell")
        integer(self.route_steps, "route_steps", 0, MAX_TRANSITIONS)
        if self.terminal_water_class is not None:
            integer(self.terminal_water_class, "terminal_water_class", 1, 3)
        if self.terminal_lake_objectid is not None:
            integer(self.terminal_lake_objectid, "terminal_lake_objectid", 1, MAX_LAKE_ID)
        if self.route_status not in STATUSES:
            raise Stop("unsupported routing claim/status")


STATUSES = ("D8_ZERO_INTERIOR", "D8_ZERO_AT_RASTER_EDGE", "D8_POINTER_NA",
            "D8_POINTER_INVALID", "D8_CYCLE", "D8_DOMAIN_EXIT", "STEP_LIMIT",
            "INVALID_WATER_CLASS", "LAKE_ID_MISSING", "RETURNS_TO_ORIGIN_LAKE",
            "REACHES_OTHER_LAKE", "REACHES_RIVER_AREA", "REACHES_RIVER_LINE")
LOCKED_SUMMARIES = tuple(Summary(rid, start, 1894, TERMINAL, None, None, steps, "D8_ZERO_INTERIOR")
                         for rid, start, steps in ((11, 23337318, 21), (14, 23343318, 22),
                                                   (15, 23343319, 22), (16, 23343320, 23),
                                                   (18, 23349320, 23), (20, 23355321, 24)))


def locked_summaries(rows):
    if type(rows) not in (list, tuple) or len(rows) != 6 or any(type(r) is not Summary for r in rows):
        raise Stop("six typed original summaries required")
    ordered = tuple(sorted(rows, key=lambda r: r.route_id))
    if ordered != LOCKED_SUMMARIES:
        raise Stop("changed/duplicate/conflicting original route identity or summary")
    return ordered


def prove_low_window(rows=LOCKED_SUMMARIES):
    rows = locked_summaries(rows)
    coords = tuple(row_col(r.start_receiver_cell) for r in rows) + (row_col(TERMINAL),)
    padding = max(r.route_steps for r in rows)
    minrow, maxrow = min(r for r, _ in coords), max(r for r, _ in coords)
    mincol, maxcol = min(c for _, c in coords), max(c for _, c in coords)
    proof = Window(mincol - padding, minrow - padding,
                   maxcol - mincol + 1 + 2 * padding, maxrow - minrow + 1 + 2 * padding)
    if proof != Window():
        raise Stop("fixed-window proof mismatch; expansion forbidden")
    return proof


@dataclass(frozen=True)
class Cell:
    cell_id: int
    row0: int
    col0: int
    x: int
    y: int
    pointer: int | float | Missing
    water_class: int | float | Missing
    lake_id: int | float | Missing

    def __post_init__(self):
        if (self.row0, self.col0) != row_col(self.cell_id) or (self.x, self.y) != center(self.cell_id):
            raise Stop("inconsistent cell geometry")
        for name in ("pointer", "water_class", "lake_id"):
            object.__setattr__(self, name, numeric(getattr(self, name), name))
        if not absent(self.lake_id) and (self.lake_id <= 0 or self.lake_id > MAX_LAKE_ID or self.lake_id != int(self.lake_id)):
            raise Stop("invalid cell lake ID")


@dataclass(frozen=True)
class Step:
    inspection: int
    source_cell: int
    pointer: int
    target_row0: int
    target_col0: int
    target_cell: int | None
    outcome: str

    def __post_init__(self):
        integer(self.inspection, "inspection", 1, MAX_INSPECTIONS)
        integer(self.pointer, "step pointer", 1, 128)
        offset = next(((dr, dc) for code, dr, dc in OFFSETS if code == self.pointer), None)
        row, col = row_col(self.source_cell)
        if offset is None or (self.target_row0, self.target_col0) != (row + offset[0], col + offset[1]):
            raise Stop("inconsistent D8 step geometry")
        expected = (cell_id(self.target_row0, self.target_col0)
                    if 0 <= self.target_row0 < 6000 and 0 <= self.target_col0 < 6000 else None)
        if self.target_cell != expected or self.outcome not in (
                "ADVANCED", "CYCLE", "DOMAIN_EXIT", "BOUNDED_WINDOW_STOP", "TRANSITION_BUDGET_STOP"):
            raise Stop("inconsistent D8 target/outcome")
        if (self.outcome == "DOMAIN_EXIT") != (expected is None):
            raise Stop("domain-exit outcome disagrees with full-grid geometry")


@dataclass(frozen=True)
class Locks:
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)


@dataclass(frozen=True)
class Trace(Locks):
    route_id: int
    start_receiver_cell: int
    origin_lake_objectid: int
    cells: tuple[Cell, ...]
    entered_cells: tuple[int, ...]
    steps: tuple[Step, ...]
    terminal_cell: int
    terminal_water_class: int | None
    terminal_lake_objectid: int | None
    route_steps: int
    route_status: str | None
    stop_reason: str | None
    content_sha256: str

    def __post_init__(self):
        integer(self.route_id, "route_id")
        integer(self.start_receiver_cell, "start_receiver_cell")
        integer(self.origin_lake_objectid, "origin_lake_objectid", 1, MAX_LAKE_ID)
        integer(self.terminal_cell, "terminal_cell")
        integer(self.route_steps, "route_steps", 0, MAX_TRANSITIONS)
        if self.route_status is not None and self.route_status not in STATUSES:
            raise Stop("unsupported trace status/authorization claim")
        if (self.stop_reason is None) == (self.route_status is None):
            raise Stop("exactly one route status or safety STOP required")
        if self.stop_reason not in (None, "OUTSIDE_BOUNDED_WINDOW", "TRANSITION_BUDGET_EXCEEDED"):
            raise Stop("unknown safety STOP")
        if (type(self.cells) is not tuple or type(self.entered_cells) is not tuple or
                type(self.steps) is not tuple or len(self.cells) > MAX_INSPECTIONS or
                len(self.entered_cells) != self.route_steps + 1 or
                len(self.steps) > MAX_INSPECTIONS or self.entered_cells[0] != self.start_receiver_cell):
            raise Stop("invalid immutable trace bounds")
        if any(type(c) is not Cell for c in self.cells) or any(type(s) is not Step for s in self.steps):
            raise Stop("typed immutable trace records required")
        if type(self.content_sha256) is not str or not re.fullmatch(r"[0-9a-f]{64}", self.content_sha256):
            raise Stop("trace source fingerprint required")
        for cell in self.entered_cells:
            integer(cell, "entered_cell")
        if len(set(self.entered_cells)) != len(self.entered_cells):
            raise Stop("cycle-closing target must not become an accepted move")
        if tuple(c.cell_id for c in self.cells) != self.entered_cells[:len(self.cells)]:
            raise Stop("inspected cells must match the entered prefix")
        advanced = tuple((st.source_cell, st.target_cell) for st in self.steps if st.outcome == "ADVANCED")
        if advanced != tuple(zip(self.entered_cells, self.entered_cells[1:])):
            raise Stop("step records disagree with accepted chain")
        for st in self.steps:
            if st.inspection > len(self.cells):
                raise Stop("pointer step requires an inspected source")
            item = self.cells[st.inspection - 1]
            if st.source_cell != item.cell_id or st.pointer != item.pointer or not absent(item.water_class):
                raise Stop("step source/pointer/land observation mismatch")
        if len({st.inspection for st in self.steps}) != len(self.steps):
            raise Stop("multiple outgoing attempts in one inspection")
        if self.route_status == "D8_CYCLE":
            if not self.steps or self.steps[-1].outcome != "CYCLE" or self.terminal_cell not in self.entered_cells:
                raise Stop("cycle must have an observed repeated target")
        elif self.terminal_cell != self.entered_cells[-1]:
            raise Stop("terminal must be the final entered cell")

    def summary(self):
        if self.stop_reason:
            raise Stop(self.stop_reason)
        return Summary(self.route_id, self.start_receiver_cell, self.origin_lake_objectid,
                       self.terminal_cell, self.terminal_water_class, self.terminal_lake_objectid,
                       self.route_steps, self.route_status)


def trace(data, route_id, start_receiver_cell, origin_lake_objectid=1894,
          max_inspections=MAX_INSPECTIONS, max_transitions=MAX_TRANSITIONS):
    """Match 02F on bounded inputs, with explicit non-02F safety STOPs.

    STEP_LIMIT counts inspections as in 02F: its tail may be entered but not
    inspected. A cycle-closing or full-domain-exiting attempt is not a move.
    """
    if type(data) is not WindowData:
        raise Stop("WindowData required")
    integer(route_id, "route_id")
    integer(start_receiver_cell, "start_receiver_cell")
    integer(origin_lake_objectid, "origin_lake_objectid", 1, MAX_LAKE_ID)
    integer(max_inspections, "max_inspections", 1, MAX_INSPECTIONS)
    integer(max_transitions, "max_transitions", 0, MAX_TRANSITIONS)
    current = start_receiver_cell
    entered, inspected, steps = [current], [], []
    visited = {current}
    status = reason = wc = lake = None
    terminal = current
    for iteration in range(1, max_inspections + 1):
        row, col = row_col(current)
        if not data.window.contains(row, col):
            reason = "OUTSIDE_BOUNDED_WINDOW"
            break
        item = data.sample(current)
        inspected.append(item)
        terminal = current
        if not absent(item.water_class):
            if item.water_class not in (1, 2, 3):
                status = "INVALID_WATER_CLASS"
            else:
                wc = int(item.water_class)
                if wc == 1:
                    lake = None if absent(item.lake_id) else int(item.lake_id)
                    status = ("LAKE_ID_MISSING" if lake is None else
                              "RETURNS_TO_ORIGIN_LAKE" if lake == origin_lake_objectid else
                              "REACHES_OTHER_LAKE")
                else:
                    status = "REACHES_RIVER_AREA" if wc == 2 else "REACHES_RIVER_LINE"
            break
        pointer = item.pointer
        if absent(pointer):
            status = "D8_POINTER_NA"
            break
        if pointer == 0:
            status = "D8_ZERO_AT_RASTER_EDGE" if row in (0, 5999) or col in (0, 5999) else "D8_ZERO_INTERIOR"
            break
        offset = next(((dr, dc) for code, dr, dc in OFFSETS if pointer == code), None)
        if offset is None:
            status = "D8_POINTER_INVALID"
            break
        nr, nc = row + offset[0], col + offset[1]
        target = cell_id(nr, nc) if 0 <= nr < 6000 and 0 <= nc < 6000 else None
        if target is None:
            outcome, status = "DOMAIN_EXIT", "D8_DOMAIN_EXIT"
        elif target in visited:
            outcome, status, terminal = "CYCLE", "D8_CYCLE", target
        elif not data.window.contains(nr, nc):
            outcome, reason = "BOUNDED_WINDOW_STOP", "OUTSIDE_BOUNDED_WINDOW"
        elif len(entered) - 1 >= max_transitions:
            outcome, reason = "TRANSITION_BUDGET_STOP", "TRANSITION_BUDGET_EXCEEDED"
        else:
            outcome = "ADVANCED"
        steps.append(Step(iteration, current, int(pointer), nr, nc, target, outcome))
        if outcome != "ADVANCED":
            break
        current = target
        entered.append(current)
        visited.add(current)
        terminal = current
    if status is None and reason is None:
        status = "STEP_LIMIT"
    return Trace(route_id, start_receiver_cell, origin_lake_objectid, tuple(inspected),
                 tuple(entered), tuple(steps), terminal, wc, lake, len(entered) - 1,
                 status, reason, data.content_sha256)


@dataclass(frozen=True)
class SharedCell:
    cell_id: int
    entered_route_ids: tuple[int, ...]
    inspected_route_ids: tuple[int, ...]


@dataclass(frozen=True)
class PairMerge:
    route_ids: tuple[int, int]
    first_shared_cell: int | None
    shared_observed_chain: tuple[int, ...]
    interpretation: str


@dataclass(frozen=True)
class TerminalGroup:
    cell_id: int
    route_outcomes: tuple  # (route_id, status, stop_reason), never collapsed into approval


@dataclass(frozen=True)
class Aggregation(Locks):
    shared_cells: tuple[SharedCell, ...]
    pairs: tuple[PairMerge, ...]
    terminal_groups: tuple[TerminalGroup, ...]
    independent_channel_count: None = field(default=None, init=False)

    def __post_init__(self):
        if any(type(v) is not tuple for v in (self.shared_cells, self.pairs, self.terminal_groups)):
            raise Stop("immutable aggregation tuples required")


def aggregate(traces):
    """Group observed cells only; never extend one trace using another trace."""
    if type(traces) not in (tuple, list) or not 1 <= len(traces) <= 6 or any(type(t) is not Trace for t in traces):
        raise Stop("one to six bounded traces required")
    traces = tuple(sorted(traces, key=lambda t: t.route_id))
    if len({t.route_id for t in traces}) != len(traces):
        raise Stop("duplicate/conflicting route IDs")
    if len({t.content_sha256 for t in traces}) != 1:
        raise Stop("incompatible in-memory source provenance")
    observations, entered, inspected, terminals = {}, {}, {}, {}
    for t in traces:
        for c in t.cells:
            if c.cell_id in observations and observations[c.cell_id] != c:
                raise Stop("contradictory shared-cell observations")
            observations[c.cell_id] = c
            inspected.setdefault(c.cell_id, []).append(t.route_id)
        for cell in t.entered_cells:
            entered.setdefault(cell, []).append(t.route_id)
        terminals.setdefault(t.terminal_cell, []).append((t.route_id, t.route_status, t.stop_reason))
    pairs = []
    for i, a in enumerate(traces):
        for b in traces[i + 1:]:
            common_a = tuple(c for c in a.entered_cells if c in b.entered_cells)
            common_b = tuple(c for c in b.entered_cells if c in a.entered_cells)
            first = common_a[0] if common_a and common_a[0] == common_b[0] else None
            chain = []
            if first is not None:
                ia, ib = a.entered_cells.index(first), b.entered_cells.index(first)
                for ca, cb in zip(a.entered_cells[ia:], b.entered_cells[ib:]):
                    if ca != cb:
                        break
                    chain.append(ca)
            interpretation = ("CYCLIC_OR_AMBIGUOUS" if any(t.route_status == "D8_CYCLE" for t in (a, b)) else
                              "SHARED_OBSERVED_CELLS_ONLY" if first is not None else "NO_SHARED_CELL")
            pairs.append(PairMerge((a.route_id, b.route_id), first, tuple(chain), interpretation))
    return Aggregation(tuple(SharedCell(c, tuple(ids), tuple(inspected.get(c, ())))
                             for c, ids in sorted(entered.items()) if len(ids) > 1),
                       tuple(pairs), tuple(TerminalGroup(c, tuple(rows)) for c, rows in sorted(terminals.items())))


@dataclass(frozen=True)
class Neighbor:
    """Normalized supplied 02C water-neighbor row, NOT an inferred route."""
    component_id: int
    source_cell: int
    water_cell: int
    water_class: int
    lake_id: int | None

    def __post_init__(self):
        integer(self.component_id, "component_id")
        integer(self.source_cell, "source_cell")
        integer(self.water_cell, "water_cell")
        integer(self.water_class, "water_class", 1, 3)
        if self.lake_id is not None:
            integer(self.lake_id, "lake_id", 1, MAX_LAKE_ID)
        r, c = row_col(self.source_cell)
        nr, nc = row_col(self.water_cell)
        if max(abs(r - nr), abs(c - nc)) != 1:
            raise Stop("02C row is not an adjacent neighbor")


def neighbor_parity(data, supplied):
    if type(supplied) not in (tuple, list) or len(supplied) != 3 or any(type(n) is not Neighbor for n in supplied):
        raise Stop("three typed 02C rows required")
    if any((n.component_id, n.source_cell, n.water_class, n.lake_id) != (274, TERMINAL, 1, 1892)
           for n in supplied) or len({n.water_cell for n in supplied}) != 3:
        raise Stop("changed/duplicate 02C neighbor identity")
    row, col = row_col(TERMINAL)
    recovered = []
    for _, dr, dc in OFFSETS:
        item = data.sample(cell_id(row + dr, col + dc))
        if absent(item.water_class):
            continue
        if item.water_class not in (1, 2, 3):
            return False
        recovered.append(Neighbor(274, TERMINAL, item.cell_id, int(item.water_class),
                                  None if item.water_class != 1 or absent(item.lake_id) else int(item.lake_id)))
    return tuple(sorted(recovered, key=lambda n: n.water_cell)) == tuple(sorted(supplied, key=lambda n: n.water_cell))


@dataclass(frozen=True)
class Comparison:
    route_id: int
    expected: Summary
    recovered: Summary | None
    mismatched_fields: tuple[str, ...]
    stop_reason: str | None


@dataclass(frozen=True)
class Audit(Locks):
    diagnostic_result: str
    S2_RESULT: str
    data_kind: str
    content_sha256: str
    provenance: Provenance
    window: Window
    stages: tuple  # (stage_name, PASS/STOP/NOT_RUN)
    traces: tuple[Trace, ...]
    comparisons: tuple[Comparison, ...]
    aggregation: Aggregation
    real_raster_parity: str = field(default="NOT_ASSESSED", init=False)
    source_authentication: str = field(default="NOT_ASSESSED", init=False)

    def __post_init__(self):
        if self.diagnostic_result not in ("PASS", "FAIL") or self.S2_RESULT not in (
                "NOT_ASSESSED", "REVIEW_REQUIRED/FAIL_CLOSED"):
            raise Stop("unsupported result/authorization claim")
        if any(type(v) is not tuple for v in (self.stages, self.traces, self.comparisons)):
            raise Stop("immutable audit tuples required")


def audit_low(data, original_summaries=LOCKED_SUMMARIES, neighbors_02c=None):
    if type(data) is not WindowData:
        raise Stop("WindowData required")
    rows = locked_summaries(original_summaries)
    if data.window != prove_low_window(rows):
        raise Stop("exact fixed 52x73 LOW window required; no expansion")
    if data.provenance.summary_sha256 != SUMMARY_SHA256:
        raise Stop("changed declared 02F version; not historical evidence")
    traces = tuple(trace(data, r.route_id, r.start_receiver_cell, r.origin_lake_objectid) for r in rows)
    comparisons = []
    for expected, recovered in zip(rows, traces):
        actual = None if recovered.stop_reason else recovered.summary()
        mismatches = () if actual is None else tuple(f.name for f in fields(Summary)
                                                     if getattr(expected, f.name) != getattr(actual, f.name))
        comparisons.append(Comparison(expected.route_id, expected, actual, mismatches, recovered.stop_reason))
    parity = all(not c.stop_reason and not c.mismatched_fields for c in comparisons)
    water_stage = "NOT_RUN" if neighbors_02c is None else "PASS" if neighbor_parity(data, neighbors_02c) else "STOP"
    good = parity and water_stage != "STOP"
    resource_ok = all(t.stop_reason is None for t in traces)
    stages = (("INPUT_QA", "PASS"), ("TRACE_PARITY", "PASS" if parity else "STOP"),
              ("WATER_NEIGHBOR_PARITY", water_stage), ("GEO_REFERENCE", "NOT_RUN"),
              ("SOURCE_PROVENANCE", "NOT_RUN"), ("AGGREGATION", "PASS"),
              ("RESOURCE_BOUND", "PASS" if resource_ok else "STOP"))
    return Audit("PASS" if good else "FAIL", "NOT_ASSESSED" if good else "REVIEW_REQUIRED/FAIL_CLOSED",
                 data.provenance.data_kind, data.content_sha256, data.provenance, data.window, stages,
                 traces, tuple(comparisons), aggregate(traces))


_RECORD_TYPES = (Grid, Window, Provenance, WindowData, Summary, Cell, Step, Locks, Trace,
                 SharedCell, PairMerge, TerminalGroup, Aggregation, Neighbor, Comparison, Audit)
