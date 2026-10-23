"""S2I-A: pure, bounded, synthetic-only typed value/event wire protocol.

No filesystem, network, OS process, raster reader, signature, trusted witness,
source authentication, historical replay, route computation or runtime launcher.
Hashing here identifies supplied *synthetic bytes*, not any real raster.
"""
from dataclasses import dataclass
from hashlib import sha256
import json
import re
import struct
import uuid

MAGIC = b"MM-S2IA\0"
WIRE_VERSION = 1
SCHEMA = "maaltamerelle.s2i-a.synthetic.v1"
NA_REAL_BITS = 0x7FF00000000007A2  # R's canonical NA_real_ payload, as uint64
NA_INTEGER_BYTES = struct.pack("<i", -2147483648)
MAX_BATCH_BYTES = 4096
MAX_CLAIM_BYTES = 8192
MAX_BATCHES = 24
MAX_VALUES_PER_BATCH = 32
MAX_TOTAL_VALUES = 512
MAX_GRID_CELLS = 81
ROLE_TYPES = {"WATER_CLASS": (1, "Byte", 1),
              "LAKE_ID": (2, "Int32", 4),
              "POINTER": (3, "Float64", 8)}
ROLE_CODES = {item[0]: role for role, item in ROLE_TYPES.items()}
TAG_CODES = {"FINITE": 1, "R_NA": 2, "NAN": 3, "POS_INF": 4,
             "NEG_INF": 5, "NA_INTEGER": 6, "NODATA": 7}
CODE_TAGS = {code: name for name, code in TAG_CODES.items()}
LOCKS = {
    "NATIONAL": "LOCKED", "MODERATE": "REVIEW_REQUIRED",
    "hydrological_validation": "NOT_ASSESSED",
    "channel_interpretation": "NOT_ASSESSED",
    "routing_authorized": False, "outlet_selection": "UNASSIGNED",
    "RUNTIME_INPUT_LINEAGE": "NOT_ASSESSED",
    "SOURCE_AUTHENTICATION": "NOT_ASSESSED",
    "historical_02f_status": "STOP",
}


class ProtocolError(ValueError):
    """A bounded synthetic protocol's fail-closed STOP reason."""


def require(condition, reason):
    if not condition:
        raise ProtocolError(reason)


def uuid4_bytes(value):
    require(type(value) is str and len(value) == 36, "RUN_ID_FORMAT")
    try:
        obj = uuid.UUID(value)
    except (ValueError, AttributeError):
        raise ProtocolError("RUN_ID_FORMAT") from None
    require(obj.version == 4 and str(obj) == value, "RUN_ID_FORMAT")
    return obj.bytes


@dataclass(frozen=True)
class Grid:
    grid_id: str
    rows: int
    cols: int
    x_origin: int
    y_origin: int


@dataclass(frozen=True)
class Scalar:
    tag: str
    raw_le: bytes


@dataclass(frozen=True)
class Batch:
    run_id: str
    attempt_id: str
    grid: Grid
    sequence: int
    role: str
    requested_cells: tuple[int, ...]
    values: tuple[Scalar, ...]


@dataclass(frozen=True)
class EncodedBatch:
    data: bytes
    synthetic_sha256: str
    evidence_scope: str = "SYNTHETIC_ONLY"
    authentication: str = "NOT_ASSESSED"


@dataclass(frozen=True)
class Review:
    disposition: str
    reason: str
    synthetic_claim_sha256: str | None
    observed_batches: int
    producer_lineage_status: str = "NOT_ASSESSED"
    source_authentication: str = "NOT_ASSESSED"
    historical_02f_status: str = "STOP"
    routing_authorized: bool = False


def _check_grid(g):
    require(type(g) is Grid, "GRID_REQUIRED")
    require(type(g.grid_id) is str and re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", g.grid_id) is not None,
            "GRID_ID")
    require(all(type(v) is int for v in (g.rows, g.cols, g.x_origin, g.y_origin)), "GRID_TYPES")
    require(1 <= g.rows <= 9 and 1 <= g.cols <= 9 and g.rows * g.cols <= MAX_GRID_CELLS,
            "SYNTHETIC_GRID_LIMIT")
    require(abs(g.x_origin) <= 100000000 and abs(g.y_origin) <= 100000000,
            "GRID_ORIGIN_LIMIT")


def _check_scalar(value, role):
    require(type(value) is Scalar and type(value.tag) is str and type(value.raw_le) is bytes,
            "SCALAR_TYPE")
    require(value.tag in TAG_CODES, "SCALAR_TAG")
    _, dtype, size = ROLE_TYPES[role]
    require(len(value.raw_le) == size, "SCALAR_WIDTH")
    if dtype == "Byte":
        require(value.tag in ("FINITE", "NODATA"), "SCALAR_TAG_DTYPE")
        require((value.raw_le[0] == 255) == (value.tag == "NODATA"), "BYTE_NODATA_TAG")
    elif dtype == "Int32":
        require(value.tag in ("FINITE", "NA_INTEGER"), "SCALAR_TAG_DTYPE")
        require((value.raw_le == NA_INTEGER_BYTES) == (value.tag == "NA_INTEGER"),
                "INT32_NA_TAG")
    else:
        bits = int.from_bytes(value.raw_le, "little")
        sign = (bits >> 63) & 1
        exponent = (bits >> 52) & 0x7FF
        mantissa = bits & ((1 << 52) - 1)
        actual = ("FINITE" if exponent != 0x7FF else
                  "NEG_INF" if sign and mantissa == 0 else
                  "POS_INF" if mantissa == 0 else
                  "R_NA" if bits == NA_REAL_BITS else "NAN")
        require(value.tag == actual, "FLOAT64_BITS_TAG_MISMATCH")


def encode_batch(batch):
    """Encode a small, typed *synthetic* callback batch; never reads raster files."""
    require(type(batch) is Batch, "BATCH_TYPE")
    _check_grid(batch.grid)
    r = uuid4_bytes(batch.run_id)
    a = uuid4_bytes(batch.attempt_id)
    require(r != a, "ATTEMPT_EQUALS_RUN")
    require(type(batch.sequence) is int and 1 <= batch.sequence <= MAX_BATCHES, "SEQUENCE_LIMIT")
    require(type(batch.role) is str and batch.role in ROLE_TYPES, "ROLE")
    require(type(batch.requested_cells) is tuple and type(batch.values) is tuple and
            1 <= len(batch.requested_cells) <= MAX_VALUES_PER_BATCH and
            len(batch.requested_cells) == len(batch.values), "CELL_VALUE_COUNT")
    require(all(type(cell) is int and 1 <= cell <= batch.grid.rows * batch.grid.cols
                for cell in batch.requested_cells), "CELL_ID_OUT_OF_GRID")
    for value in batch.values:
        _check_scalar(value, batch.role)
    g = batch.grid
    gid = g.grid_id.encode("ascii")
    buf = bytearray(MAGIC)
    buf.extend(struct.pack("<B", WIRE_VERSION))
    buf.extend(r)
    buf.extend(a)
    buf.extend(struct.pack("<B", len(gid)))
    buf.extend(gid)
    # Two-dimensional row-major 1-based cell index, EPSG:3067, 2m,
    # affine [x_origin,2,0,y_origin,0,-2]; these are protocol declarations.
    buf.extend(struct.pack("<HHiiHBH", g.rows, g.cols, g.x_origin, g.y_origin,
                           batch.sequence, ROLE_TYPES[batch.role][0], len(batch.values)))
    for cell, value in zip(batch.requested_cells, batch.values):
        buf.extend(struct.pack("<HB", cell, TAG_CODES[value.tag]))
        buf.extend(value.raw_le)
    require(len(buf) <= MAX_BATCH_BYTES, "BYTE_BUDGET")
    raw = bytes(buf)
    return EncodedBatch(raw, sha256(raw).hexdigest())


def decode_batch(data):
    """Strictly parse the exact versioned wire grammar, rejecting trailing bytes."""
    require(type(data) is bytes and 0 < len(data) <= MAX_BATCH_BYTES, "WIRE_SIZE")
    pos = 0
    def take(count):
        nonlocal pos
        require(0 <= count <= MAX_BATCH_BYTES and pos + count <= len(data), "WIRE_TRUNCATED")
        block = data[pos:pos + count]
        pos += count
        return block
    require(take(len(MAGIC)) == MAGIC, "WIRE_MAGIC")
    require(take(1)[0] == WIRE_VERSION, "WIRE_VERSION")
    run_id = str(uuid.UUID(bytes=take(16)))
    attempt_id = str(uuid.UUID(bytes=take(16)))
    n = take(1)[0]
    require(1 <= n <= 32, "GRID_ID")
    try:
        grid_id = take(n).decode("ascii")
    except UnicodeDecodeError:
        raise ProtocolError("GRID_ID") from None
    rows, cols, x, y, sequence, role_code, count = struct.unpack("<HHiiHBH", take(17))
    require(role_code in ROLE_CODES, "ROLE")
    role = ROLE_CODES[role_code]
    require(1 <= count <= MAX_VALUES_PER_BATCH, "CELL_VALUE_COUNT")
    size = ROLE_TYPES[role][2]
    cells, values = [], []
    for _ in range(count):
        cell, tag_code = struct.unpack("<HB", take(3))
        require(tag_code in CODE_TAGS, "SCALAR_TAG")
        cells.append(cell)
        values.append(Scalar(CODE_TAGS[tag_code], take(size)))
    require(pos == len(data), "WIRE_TRAILING_BYTES")
    b = Batch(run_id, attempt_id, Grid(grid_id, rows, cols, x, y), sequence,
              role, tuple(cells), tuple(values))
    require(encode_batch(b).data == data, "WIRE_NONCANONICAL")
    return b


def _decode_observed(observed):
    require(type(observed) is tuple and 1 <= len(observed) <= MAX_BATCHES, "BATCH_COUNT")
    require(all(type(item) is bytes for item in observed), "OBSERVED_BYTES_ONLY")
    batches = tuple(decode_batch(item) for item in observed)
    require(sum(len(b.values) for b in batches) <= MAX_TOTAL_VALUES, "VALUE_BUDGET")
    first = batches[0]
    for i, b in enumerate(batches, start=1):
        require(b.run_id == first.run_id and b.attempt_id == first.attempt_id and
                b.grid == first.grid, "RUN_SCOPE_MISMATCH")
        require(b.sequence == i, "EVENT_SEQUENCE")
        require(b.role == ("WATER_CLASS", "LAKE_ID", "POINTER")[(i - 1) % 3],
                "CALLBACK_ROLE_ORDER")
        if i % 3 != 1:
            require(b.requested_cells == batches[i - 2 if i % 3 == 2 else i - 3].requested_cells,
                    "TRIPLET_CELL_MISMATCH")
    return batches


def make_synthetic_claim(observed, *, declared_status="COMPLETE_CLAIM"):
    """Create a *self-declared* JSON claim about synthetic bytes, not a witness."""
    require(declared_status in ("COMPLETE_CLAIM", "INCOMPLETE"), "DECLARED_STATUS")
    batches = _decode_observed(observed)
    claim = dict(schema_version=SCHEMA, evidence_kind="SYNTHETIC",
                 run_id=batches[0].run_id, attempt_id=batches[0].attempt_id,
                 declared_status=declared_status,
                 batch_sha256=[sha256(b).hexdigest() for b in observed],
                 witness=None, **LOCKS)
    data = json.dumps(claim, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("ascii")
    require(len(data) <= MAX_CLAIM_BYTES, "CLAIM_SIZE")
    return data


def _reject_duplicate(pairs):
    result = {}
    for k, value in pairs:
        require(k not in result, "DUPLICATE_JSON_KEY")
        result[k] = value
    return result


def _reject_constant(value):
    raise ProtocolError("NONFINITE_JSON")


def verify_synthetic_claim(raw, observed):
    """Fail closed; a positive syntactic review is always RECORDED_UNVERIFIED.

    Claims and observed byte batches are passed in memory by the SAME caller;
    this routine is not independent witness/signature/source authentication.
    """
    try:
        require(type(raw) is bytes and 0 < len(raw) <= MAX_CLAIM_BYTES, "CLAIM_SIZE")
        require(all(c < 128 for c in raw), "NONASCII_CLAIM")
        value = json.loads(raw.decode("ascii"), object_pairs_hook=_reject_duplicate,
                           parse_constant=_reject_constant)
        require(type(value) is dict, "CLAIM_TYPE")
        canonical = json.dumps(value, sort_keys=True, separators=(",", ":"),
                               ensure_ascii=True).encode("ascii")
        require(raw == canonical, "CLAIM_NONCANONICAL")
        expected = (set(LOCKS) | {"schema_version", "evidence_kind", "run_id",
                                  "attempt_id", "declared_status", "batch_sha256", "witness"})
        require(set(value) == expected, "CLAIM_FIELDS")
        for k, v in LOCKS.items():
            require(type(value[k]) is type(v) and value[k] == v, "FORBIDDEN_AUTHORITY_CLAIM")
        require(value["schema_version"] == SCHEMA, "CLAIM_SCHEMA")
        require(value["evidence_kind"] == "SYNTHETIC" and value["witness"] is None,
                "FORBIDDEN_WITNESS_OR_REAL_SCOPE")
        require(type(value["run_id"]) is str and type(value["attempt_id"]) is str,
                "RUN_ID_FORMAT")
        uuid4_bytes(value["run_id"])
        uuid4_bytes(value["attempt_id"])
        require(type(value["declared_status"]) is str and
                value["declared_status"] in ("COMPLETE_CLAIM", "INCOMPLETE"), "DECLARED_STATUS")
        require(type(value["batch_sha256"]) is list and
                1 <= len(value["batch_sha256"]) <= MAX_BATCHES and
                all(type(h) is str and re.fullmatch("[0-9a-f]{64}", h) for h in value["batch_sha256"]),
                "BATCH_HASH_FORMAT")
        batches = _decode_observed(observed)
        require(len(batches) == len(value["batch_sha256"]), "BATCH_COUNT_MISMATCH")
        require(value["run_id"] == batches[0].run_id and
                value["attempt_id"] == batches[0].attempt_id, "RUN_SCOPE_MISMATCH")
        for item, claimed_digest in zip(observed, value["batch_sha256"]):
            require(sha256(item).hexdigest() == claimed_digest, "SYNTHETIC_DIGEST_MISMATCH")
        require(len(batches) % 3 == 0 and value["declared_status"] == "COMPLETE_CLAIM",
                "INCOMPLETE_TRIPLET_OR_CLAIM")
        return Review("RECORDED_UNVERIFIED", "NO_INDEPENDENT_WITNESS", sha256(raw).hexdigest(), len(batches))
    except (ProtocolError, UnicodeDecodeError, json.JSONDecodeError, ValueError, TypeError, RecursionError, OverflowError) as exc:
        reason = str(exc) if type(exc) is ProtocolError else "MALFORMED_CLAIM"
        return Review("STOP", reason[:100], None, 0)