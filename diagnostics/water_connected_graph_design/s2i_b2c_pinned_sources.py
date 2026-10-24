"""Offline, read-only Git selector for the three frozen R dependencies.

Preparation only: never invokes R, fetch, merge, checkout, CSC or model data.
Python 3.9+ syntax permits a host preparation stage outside CSC containers.
"""
import argparse
import hashlib
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import sys
import time

S2F_PIN = "477c5b13d5714d618c9c9de88f5f80290b53d994"
BASE_PIN = "8d94ec33ce3aeeb20626b6665ae81594934087ce"
ORIGIN = "https://github.com/annasuuronen/MaaltaMerelle.git"
SOURCES = (
    ("native", S2F_PIN, "R/02F_water_connected_route_diagnostics.R",
     "36df1b8181cb9c604f82c3c11970ec2d553bbb59385d4a693ae5f72159447ccf"),
    ("observer", S2F_PIN, "diagnostics/water_connected_graph_design/s2f_synthetic_02f_observer.R",
     "81e8fa53a6117facb6cd70e3c03a2c3cd79eef77b75cda074011095ad88ab9dc"),
    ("codec", BASE_PIN, "diagnostics/water_connected_graph_design/s2i_b2b_native_value_v2.R",
     "869a253ca626899d54070e0e7665da88c9fd881e1a4f7ba3fb95da4781b6e95a"),
)
MAX_BLOB = 32768
MAX_LOADER = 262144


class Stop(ValueError):
    status = "STOP"
    NATIONAL = "LOCKED"
    MODERATE = "REVIEW_REQUIRED"
    hydrological_validation = "NOT_ASSESSED"
    channel_interpretation = "NOT_ASSESSED"
    outlet_selection = "UNASSIGNED"
    SOURCE_AUTHENTICATION = "NOT_ASSESSED"
    HISTORIC_02F_EFFECTIVE_D8 = "NOT_ASSESSED"
    routing_authorized = False


def need(ok, reason):
    if not ok:
        raise Stop(reason)


def git_environment():
    env = dict(os.environ)
    for key in ("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_NAMESPACE",
                "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_REPLACE_REF_BASE",
                "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG"):
        env.pop(key, None)
    for key in list(env):
        if key.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_", "GIT_TRACE")):
            env.pop(key)
    env.update(GIT_NO_LAZY_FETCH="1", GIT_NO_REPLACE_OBJECTS="1", GIT_OPTIONAL_LOCKS="0",
               GIT_ALLOW_PROTOCOL="", GIT_PROTOCOL_FROM_USER="0", GIT_TERMINAL_PROMPT="0",
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_PAGER="cat",
               LC_ALL="C")
    return env


def git_read(repo, args, deadline, limit=MAX_BLOB):
    binary = shutil.which("git")
    need(binary is not None, "GIT_UNAVAILABLE")
    cmd = [binary, "--no-pager", "-c", "core.hooksPath=" + os.devnull,
           "-c", "core.fsmonitor=false", "-c", "protocol.allow=never", "-C", str(repo)] + list(args)
    need(time.monotonic() < deadline, "PREPARE_TIMEOUT")
    with subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=git_environment(), shell=False) as proc:
        out, err = bytearray(), bytearray()
        with selectors.DefaultSelector() as sel:
            sel.register(proc.stdout, selectors.EVENT_READ, out)
            sel.register(proc.stderr, selectors.EVENT_READ, err)
            try:
                while sel.get_map():
                    remaining = min(5.0, deadline - time.monotonic())
                    need(remaining > 0, "GIT_TIMEOUT")
                    events = sel.select(remaining)
                    need(bool(events), "GIT_TIMEOUT")
                    for key, _ in events:
                        chunk = os.read(key.fileobj.fileno(), 4096)
                        if not chunk:
                            sel.unregister(key.fileobj)
                            continue
                        key.data.extend(chunk)
                        need(len(out) <= limit and len(err) <= 4096, "GIT_OUTPUT_LIMIT")
                rc = proc.wait(timeout=max(0.01, min(5.0, deadline-time.monotonic())))
                need(rc == 0 and not err, "GIT_READ_STOP")
            except BaseException:
                proc.kill()
                proc.wait()
                raise
        return bytes(out)


def verify_blob(role, data):
    expected = {r: digest for r, _, _, digest in SOURCES}
    need(type(role) is str and 1 <= len(role) <= 8 and role in expected and
         type(data) is bytes and 0 < len(data) <= MAX_BLOB, "BLOB_SCOPE")
    need(hashlib.sha256(data).hexdigest() == expected[role], "SOURCE_BYTES_MISMATCH")
    # Source is fixed reviewed text; binary/NUL content is never a source argument.
    need(b"\0" not in data, "SOURCE_NUL")
    try:
        data.decode("utf-8")
    except UnicodeError:
        raise Stop("SOURCE_TEXT") from None


def render(blobs):
    need(type(blobs) is dict and len(blobs) == 3 and set(blobs) == {"native", "observer", "codec"}, "SOURCE_SET")
    for role, data in blobs.items():
        verify_blob(role, data)
    # Only verified hex is embedded. No user path/source text is interpolated.
    load = """# Generated from fixed verified Git blobs; local code identity, not data provenance.
s2c_dependencies <- local({
  unhex <- function(h) as.raw(strtoi(substring(h,seq.int(1L,nchar(h),2L),
                                             seq.int(2L,nchar(h),2L)),16L))
  read_code <- function(h,e) {
    con <- textConnection(rawToChar(unhex(h)))
    on.exit(close(con))
    source(con,local=e,echo=FALSE,keep.source=FALSE)
  }
  s2f <- new.env(parent=asNamespace("stats"))
  codec <- new.env(parent=baseenv())
"""
    for role, target in (("native", "s2f"), ("observer", "s2f"), ("codec", "codec")):
        load += '  read_code("' + blobs[role].hex() + '",' + target + ')\n'
    load += '''  lockEnvironment(s2f,bindings=TRUE)
  lockEnvironment(codec,bindings=TRUE)
  result <- new.env(parent=emptyenv())
  result$s2f <- s2f; result$codec <- codec
  result$pins <- list(S2F="''' + S2F_PIN + '",V2="' + BASE_PIN + '''")
  class(result) <- "s2c_dependencies"
  lockEnvironment(result,bindings=TRUE)
  result
})
'''
    raw = load.encode("ascii")
    need(len(raw) <= MAX_LOADER, "LOADER_SIZE")
    return raw


def build_bootstrap(repo):
    repo = Path(repo).resolve(strict=True)
    need(repo.is_dir(), "REPOSITORY_DIRECTORY")
    deadline = time.monotonic() + 20
    root = git_read(repo, ("rev-parse", "--show-toplevel"), deadline, 4096).strip()
    need(Path(os.fsdecode(root)).resolve() == repo, "REPOSITORY_ROOT")
    origin = git_read(repo, ("config", "--local", "--no-includes", "--get", "remote.origin.url"),
                      deadline, 2048).strip()
    need(origin == ORIGIN.encode("ascii"), "CANONICAL_ORIGIN_REQUIRED")
    for pin in (S2F_PIN, BASE_PIN):
        need(git_read(repo, ("cat-file", "-t", pin), deadline, 64) == b"commit\n", "COMMIT_TYPE")
    blobs = {}
    for role, pin, path, _ in SOURCES:
        obj = pin + ":" + path
        raw_size = git_read(repo, ("cat-file", "-s", obj), deadline, 64).strip()
        need(raw_size.isdigit() and 0 < int(raw_size) <= MAX_BLOB, "BLOB_SIZE")
        data = git_read(repo, ("show", "--no-textconv", obj), deadline)
        need(len(data) == int(raw_size), "BLOB_SIZE_CHANGED")
        verify_blob(role, data)
        blobs[role] = data
    common = git_read(repo, ("show", "--no-textconv", BASE_PIN + ":" + SOURCES[0][2]), deadline)
    need(common == blobs["native"], "NATIVE_BASE_DIVERGED")
    return render(blobs)


def write_new_private(path, data):
    need(type(data) is bytes and 0 < len(data) <= MAX_LOADER, "LOADER_SIZE")
    path = Path(path)
    need(path.is_absolute() and path.name not in ("", ".", ".."), "PRIVATE_OUTPUT_PATH")
    parent = path.parent.resolve(strict=True)
    need(parent == path.parent, "OUTPUT_SYMLINK_PARENT")
    info = parent.stat()
    need(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) & 0o077 == 0,
         "PRIVATE_OUTPUT_DIRECTORY")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def main():
    p = argparse.ArgumentParser(description="Prepare frozen synthetic R dependencies offline; never run R")
    p.add_argument("--repo", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    try:
        data = build_bootstrap(a.repo)
        write_new_private(a.output, data)
    except (Stop, OSError, subprocess.SubprocessError):
        print("S2C_SOURCE_PREPARE=STOP", file=sys.stderr)
        return 2
    print("S2C_SOURCE_PREPARE=LOCAL_CODE_BYTES_MATCH_NOT_AUTHENTICATED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
