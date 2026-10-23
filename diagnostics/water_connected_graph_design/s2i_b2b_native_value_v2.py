"""Standalone MM-S2CV v2 synthetic codec. No raster, process, file or S2F API.

Raw bytes and observed validity are data, never authenticated observations.
NA_REAL and NAN share the IEEE NaN category; their distinction is reference data.
"""
from dataclasses import dataclass, field
from hashlib import sha256
import re
import struct
import uuid


@dataclass(frozen=True, slots=True)
class Safety:
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)
    HISTORIC_02F_EFFECTIVE_D8: str = field(default="NOT_ASSESSED", init=False)
    SOURCE_AUTHENTICATION: str = field(default="NOT_ASSESSED", init=False)
    INDEPENDENT_WITNESS: str = field(default="NOT_IMPLEMENTED", init=False)


SAFETY = Safety()
MAGIC = b"MM-S2CV\0"
END = b"MM-END2\0"
LIMIT = 16384
_TYPES = {"INTEGER": (1, 4), "DOUBLE": (2, 8)}
_ROLES = {"WATER_CLASS": 1, "LAKE_ID": 2, "POINTER": 3}
_TAGS = {"FINITE": 1, "NA_INTEGER": 2, "NA_REAL": 3,
         "NAN": 4, "POS_INF": 5, "NEG_INF": 6}
_CELL_DOUBLES = {struct.pack("<d", n): n for n in range(1, 82)}


class _Safe:
    __slots__ = ()

    @property
    def safety(self):
        return SAFETY


class Stop(ValueError, _Safe):
    """Fail-closed synthetic codec error; message contains a bounded reason only."""

    status = "STOP"


def _need(ok, reason):
    if not ok:
        raise Stop(reason)


@dataclass(frozen=True, slots=True)
class Header(_Safe):
    run_id: str
    attempt_id: str
    grid_id: str
    rows: int
    cols: int
    x_origin: int
    y_origin: int
    r_version: str
    r_platform: str
    declared_dtypes: tuple[int, int, int] = (0, 0, 0)


@dataclass(frozen=True, slots=True)
class Request(_Safe):
    storage_type: str
    raw_le: bytes


@dataclass(frozen=True, slots=True)
class Values(_Safe):
    storage_type: str
    validity: tuple[str, ...]
    raw_le: bytes


@dataclass(frozen=True, slots=True)
class Batch(_Safe):
    sequence: int
    role: str
    request: Request
    response: Values


@dataclass(frozen=True, slots=True)
class Transcript(_Safe):
    header: Header
    batches: tuple[Batch, ...]


@dataclass(frozen=True, slots=True)
class Encoded(_Safe):
    data: bytes
    synthetic_payload_sha256: str
    disposition: str = field(default="STRUCTURALLY_WELL_FORMED", init=False)
    authentication: str = field(default="NOT_AUTHENTICATED", init=False)


@dataclass(frozen=True, slots=True)
class Decoded(_Safe):
    transcript: Transcript
    disposition: str = field(default="STRUCTURALLY_WELL_FORMED", init=False)
    authentication: str = field(default="NOT_AUTHENTICATED", init=False)


@dataclass(frozen=True, slots=True)
class ReferenceMatch(_Safe):
    synthetic_payload_sha256: str
    comparison: str = field(default="SYNTHETIC_REFERENCE_BYTES_MATCH", init=False)
    disposition: str = field(default="RECORDED_UNVERIFIED", init=False)
    LOCAL_OBSERVATION_MATCH: str = field(default="NOT_ASSESSED", init=False)


def _integer(x, lo, hi, reason):
    _need(type(x) is int and lo <= x <= hi, reason)


def _text(x, pattern, maximum, reason):
    _need(type(x) is str and 1 <= len(x) <= maximum and
          re.fullmatch(pattern, x, flags=re.ASCII) is not None, reason)


def _uuid(x):
    _text(x, r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", 36, "UUID4")
    return uuid.UUID(x).bytes


def _header(h):
    _need(type(h) is Header, "HEADER_TYPE")
    run, attempt = _uuid(h.run_id), _uuid(h.attempt_id)
    _need(run != attempt, "ATTEMPT_EQUALS_RUN")
    _text(h.grid_id, r"[a-z][a-z0-9_-]{0,31}", 32, "GRID_ID")
    _integer(h.rows, 1, 9, "GRID_ROWS")
    _integer(h.cols, 1, 9, "GRID_COLS")
    _integer(h.x_origin, -100000000, 100000000, "GRID_ORIGIN")
    _integer(h.y_origin, -100000000, 100000000, "GRID_ORIGIN")
    _text(h.r_version, r"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}", 32, "R_VERSION")
    _text(h.r_platform, r"[A-Za-z0-9._-]{1,64}", 64, "R_PLATFORM")
    _need(type(h.declared_dtypes) is tuple and len(h.declared_dtypes) == 3, "DTYPE_DECLARATIONS")
    for d in h.declared_dtypes:
        _integer(d, 0, 3, "DTYPE_DECLARATIONS")
    return run, attempt


def _width(storage):
    _need(type(storage) is str and 1 <= len(storage) <= 7 and storage in _TYPES, "NATIVE_TYPE")
    return _TYPES[storage][1]


def _response(v):
    _need(type(v) is Values, "VALUES_TYPE")
    width = _width(v.storage_type)
    _need(type(v.validity) is tuple and 1 <= len(v.validity) <= 32, "VALUE_COUNT")
    _need(type(v.raw_le) is bytes and len(v.raw_le) == width * len(v.validity), "VALUE_WIDTH")
    for i, tag in enumerate(v.validity):
        _need(type(tag) is str and 1 <= len(tag) <= 10 and tag in _TAGS, "VALIDITY_TAG")
        bits = int.from_bytes(v.raw_le[i * width:(i + 1) * width], "little")
        if width == 4:
            _need(tag == ("NA_INTEGER" if bits == 0x80000000 else "FINITE"), "TAG_BITS")
        else:
            exponent, mantissa = (bits >> 52) & 2047, bits & ((1 << 52) - 1)
            if exponent != 2047:
                _need(tag == "FINITE", "TAG_BITS")
            elif mantissa:
                _need(tag in ("NA_REAL", "NAN"), "TAG_BITS")
            else:
                _need(tag == ("NEG_INF" if bits >> 63 else "POS_INF"), "TAG_BITS")
    return width


def _request(r, count, cells):
    _need(type(r) is Request, "REQUEST_TYPE")
    width = _width(r.storage_type)
    _need(type(r.raw_le) is bytes and len(r.raw_le) == count * width, "REQUEST_WIDTH")
    for i in range(count):
        raw = r.raw_le[i * width:(i + 1) * width]
        cell = int.from_bytes(raw, "little", signed=True) if width == 4 else _CELL_DOUBLES.get(raw, 0)
        _need(1 <= cell <= cells, "REQUEST_CELL")
    return width


def _transcript(t):
    _need(type(t) is Transcript, "TRANSCRIPT_TYPE")
    _header(t.header)
    _need(type(t.batches) is tuple and 3 <= len(t.batches) <= 24 and len(t.batches) % 3 == 0,
          "COMPLETE_TRIPLETS")
    slots, types = 0, {}
    for i, b in enumerate(t.batches, 1):
        _need(type(b) is Batch, "BATCH_TYPE")
        _integer(b.sequence, i, i, "SEQUENCE")
        role = ("WATER_CLASS", "LAKE_ID", "POINTER")[(i - 1) % 3]
        _need(type(b.role) is str and b.role == role, "ROLE_SEQUENCE")
        _response(b.response)
        count = len(b.response.validity)
        _request(b.request, count, t.header.rows * t.header.cols)
        slots += count
        _need(slots <= 512, "SLOT_LIMIT")
        if i % 3 != 1:
            _need(b.request == t.batches[((i - 1) // 3) * 3].request, "TRIPLET_REQUEST")
        _need(types.setdefault(role, b.response.storage_type) == b.response.storage_type,
              "ROLE_STORAGE_CHANGED")
    return slots


def _ascii(s):
    raw = s.encode("ascii")
    return bytes((len(raw),)) + raw


def encode(t):
    """Encode explicit synthetic native bytes; role never determines their dtype."""
    slots = _transcript(t)
    h = t.header
    run, attempt = _header(h)
    out = bytearray(MAGIC + bytes((2, 1, 1)) + b"\0" * 4)
    out.extend(run + attempt + _ascii(h.grid_id))
    out.extend(struct.pack("<HHIiiBBB", h.rows, h.cols, 3067, h.x_origin, h.y_origin, 2, 1, 1))
    out.extend(_ascii(h.r_version) + _ascii(h.r_platform) + bytes(h.declared_dtypes))
    out.extend(struct.pack("<HI", len(t.batches), slots))
    for b in t.batches:
        n = len(b.response.validity)
        rw, vw = _TYPES[b.request.storage_type][1], _TYPES[b.response.storage_type][1]
        body = bytearray(struct.pack("<HBBBH", b.sequence, _ROLES[b.role],
                                    _TYPES[b.request.storage_type][0], _TYPES[b.response.storage_type][0], n))
        for i, tag in enumerate(b.response.validity):
            body.extend(b.request.raw_le[i * rw:(i + 1) * rw])
            body.append(_TAGS[tag])
            body.extend(b.response.raw_le[i * vw:(i + 1) * vw])
        out.extend(struct.pack("<H", len(body)) + body)
    out.extend(END + struct.pack("<HI", len(t.batches), slots))
    _need(len(out) <= LIMIT, "BYTE_LIMIT")
    out[11:15] = struct.pack("<I", len(out))
    raw = bytes(out)
    return Encoded(raw, sha256(raw).hexdigest())


class _Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, n):
        _need(0 <= n <= LIMIT and self.pos + n <= len(self.data), "TRUNCATED")
        out = self.data[self.pos:self.pos + n]
        self.pos += n
        return out

    def number(self, fmt):
        return struct.unpack("<" + fmt, self.take(struct.calcsize("<" + fmt)))[0]

    def text(self, maximum):
        n = self.number("B")
        _need(1 <= n <= maximum, "TEXT_LENGTH")
        try:
            return self.take(n).decode("ascii")
        except UnicodeError:
            raise Stop("ASCII") from None


def _enum(code, mapping, reason):
    for name, value in mapping.items():
        if code == (value[0] if type(value) is tuple else value):
            return name
    raise Stop(reason)


def decode(data):
    """Strict v2-only parse; output promises structure, not observed source truth."""
    _need(type(data) is bytes and 0 < len(data) <= LIMIT, "WIRE_SIZE")
    r = _Reader(data)
    _need(r.take(8) == MAGIC, "MAGIC")
    _need(r.number("B") == 2, "VERSION")
    _need(r.number("B") == 1, "SCOPE")
    _need(r.number("B") == 1, "PROFILE")
    _need(r.number("I") == len(data), "TOTAL_LENGTH")
    run, attempt = str(uuid.UUID(bytes=r.take(16))), str(uuid.UUID(bytes=r.take(16)))
    grid = r.text(32)
    rows, cols, crs, x, y, size, direction, indexing = struct.unpack("<HHIiiBBB", r.take(19))
    _need((crs, size, direction, indexing) == (3067, 2, 1, 1), "GRID_PROFILE")
    header = Header(run, attempt, grid, rows, cols, x, y, r.text(32), r.text(64), tuple(r.take(3)))
    _header(header)
    count, slots = r.number("H"), r.number("I")
    _need(3 <= count <= 24 and count % 3 == 0, "COMPLETE_TRIPLETS")
    _need(1 <= slots <= 512, "SLOT_LIMIT")
    batches, observed_slots = [], 0
    for _ in range(count):
        length = r.number("H")
        _need(16 <= length <= 551, "BODY_LENGTH")
        f = _Reader(r.take(length))
        seq, role, req_type, val_type, n = struct.unpack("<HBBBH", f.take(7))
        role = _enum(role, _ROLES, "ROLE")
        req_type = _enum(req_type, _TYPES, "NATIVE_TYPE")
        val_type = _enum(val_type, _TYPES, "NATIVE_TYPE")
        _need(1 <= n <= 32, "VALUE_COUNT")
        observed_slots += n
        _need(observed_slots <= 512, "SLOT_LIMIT")
        rw, vw = _TYPES[req_type][1], _TYPES[val_type][1]
        _need(length == 7 + n * (rw + 1 + vw), "BODY_LENGTH")
        requests, responses, tags = bytearray(), bytearray(), []
        for _ in range(n):
            requests.extend(f.take(rw))
            tags.append(_enum(f.number("B"), _TAGS, "VALIDITY_TAG"))
            responses.extend(f.take(vw))
        _need(f.pos == length, "BODY_LENGTH")
        batches.append(Batch(seq, role, Request(req_type, bytes(requests)),
                             Values(val_type, tuple(tags), bytes(responses))))
    _need(observed_slots == slots, "SLOT_COUNT")
    _need(r.take(8) == END, "END_MAGIC")
    _need(r.number("H") == count and r.number("I") == slots, "END_COUNTS")
    _need(r.pos == len(data), "TRAILING_BYTES")
    t = Transcript(header, tuple(batches))
    _need(encode(t).data == data, "NONCANONICAL")
    return Decoded(t)


def compare_synthetic_reference(data, reference):
    """Compare caller-supplied bytes, never S2F reports or authenticated evidence."""
    _need(reference is not None, "REFERENCE_UNAVAILABLE")
    decode(data)
    decode(reference)
    _need(data == reference, "REFERENCE_BYTES_MISMATCH")
    return ReferenceMatch(sha256(data).hexdigest())
