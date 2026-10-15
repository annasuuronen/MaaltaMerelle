"""Static Actions isolation contracts; this module never starts a workflow.

Legacy workflows are discovered from the checkout and checked for event
isolation. Their bytes, step bodies and inventory are not permanently frozen.
Preservation in a particular change is checked separately in its Git diff.
Only the narrow YAML structures used by these workflows are read; no YAML
loader, subprocess, network connection or hydrology execution is required.
"""

import ast
import fnmatch
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"
PREFLIGHT = WORKFLOWS / "csc-preflight.yml"
CHECKOUT_SHA = "11bd71901bbe5b1630ceea73d27597364c9af683"
# Verified using read-only official refs/tags/v4.2.2 before implementation.


def legacy_workflow_sources():
    """Include current YAML workflows without pinning names, counts or bytes."""
    return {
        path.name: path.read_text(encoding="utf-8")
        for path in sorted(WORKFLOWS.iterdir())
        if path.is_file() and path.suffix in {".yml", ".yaml"} and path != PREFLIGHT
    }


def block(text, key, indentation=0):
    """Read one block-style key, rejecting duplicates in the inspected scope."""
    lines = text.splitlines()
    header = " " * indentation + key + ":"
    starts = [index for index, line in enumerate(lines) if line == header]
    if not starts:
        return None
    if len(starts) != 1:
        raise ValueError("duplicate block: " + key)
    start = starts[0]
    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.strip() and not line.lstrip().startswith("#"):
            if len(line) - len(line.lstrip()) <= indentation:
                end = index
                break
    return "\n".join(lines[start + 1 : end])


def list_values(text):
    if text is None:
        return []
    values = []
    for line in text.splitlines():
        value = line.strip()
        if not value or value.startswith("#"):
            continue
        if not value.startswith("- "):
            raise ValueError("expected a scalar-list item: " + line)
        value = value[2:].strip()
        if value.startswith(("'", '"')):
            value = ast.literal_eval(value)
        if not isinstance(value, str) or not value:
            raise ValueError("expected a nonempty scalar string")
        values.append(value)
    return values


def path_matches(path, patterns):
    """Apply ordered inclusion/exclusion patterns for this fixed path inventory.

    The preserved legacy patterns use literals and /**. Their relevant matches
    agree with fnmatch for the proposed files; this is not a general Actions
    glob implementation.
    """
    included = False
    for pattern in patterns:
        negative = pattern.startswith("!")
        if fnmatch.fnmatchcase(path, pattern[1:] if negative else pattern):
            included = not negative
    return included


def legacy_events(source):
    """Reject new automatic entry points; unsupported event syntax fails closed."""
    events = block(source, "on")
    if events is None:
        raise ValueError("expected block-style workflow events")
    names = []
    for line in events.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if len(line) - len(line.lstrip()) == 2:
            match = re.fullmatch(r"  ([a-z_]+):", line)
            if match is None:
                raise ValueError("unsupported workflow event syntax")
            names.append(match.group(1))
    if not names or len(names) != len(set(names)):
        raise ValueError("missing or duplicate workflow events")
    if set(names) - {"push", "workflow_dispatch", "workflow_run"}:
        raise ValueError("legacy workflow has an unsafe automatic trigger")
    return events


class WorkflowIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = PREFLIGHT.read_text(encoding="utf-8")

    def test_new_paths_cannot_start_existing_push_workflows(self):
        paths = {
            ".github/workflows/csc-preflight.yml",
            "automation/csc/validate_manifest.py",
            "automation/csc/run_manifest.schema.json",
            "automation/csc/report.schema.json",
            "automation/csc/tests/test_workflow.py",
            "automation/csc/requirements-preflight.lock",
            "docs/csc/AUTOMATION.md",
        }
        paths.update(
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / "automation" / "csc").rglob("*")
            if path.is_file()
        )
        self.assertFalse(any(path.startswith("tests/") for path in paths))
        for filename, source in legacy_workflow_sources().items():
            push = block(legacy_events(source), "push", 2)
            if push is None:
                continue
            self.assertEqual(list_values(block(push, "branches", 4)), ["baseline-no-structures"])
            patterns = list_values(block(push, "paths", 4))
            self.assertTrue(patterns, "an unrestricted legacy push trigger is unsafe")
            for path in paths:
                with self.subTest(workflow=filename, path=path):
                    self.assertFalse(path_matches(path, patterns))

    def test_legacy_triggers_cannot_start_or_follow_preflight(self):
        for filename, source in legacy_workflow_sources().items():
            with self.subTest(workflow=filename):
                events = legacy_events(source)
                followup = block(events, "workflow_run", 2)
                if followup is not None:
                    self.assertEqual(list_values(block(followup, "branches", 4)), ["baseline-no-structures"])
                    watched = list_values(block(followup, "workflows", 4))
                    self.assertTrue(watched, "unrestricted workflow_run is unsafe")
                    self.assertFalse(any(fnmatch.fnmatchcase("CSC preflight", name) for name in watched),
                                     "legacy continuation must not watch preflight")

    def test_benign_legacy_content_edits_do_not_require_new_hashes(self):
        source = "on:\n  workflow_dispatch:\njobs:\n  audit:\n    name: Original audit\n"
        edited = "# Approved documentation update\n" + source.replace("Original audit", "Updated audit")
        self.assertEqual(legacy_events(source), legacy_events(edited))

    def test_unsafe_legacy_event_additions_are_rejected(self):
        for event in ("pull_request", "pull_request_target", "create", "schedule", "repository_dispatch"):
            with self.subTest(event=event), self.assertRaises(ValueError):
                legacy_events("on:\n  workflow_dispatch:\n  " + event + ":\n")
        for events in ("on: [push]\n", "on:\n  push: {}\n", "on:\n  push:\n  push:\n"):
            with self.subTest(events=events), self.assertRaises(ValueError):
                legacy_events(events)

    def test_pull_requests_always_report_the_stable_check(self):
        events = block(self.workflow, "on")
        self.assertIsNotNone(events)
        self.assertEqual(
            re.findall(r"^  ([a-z_]+):$", events, re.MULTILINE),
            ["pull_request"],
        )
        pull_request = block(events, "pull_request", 2)
        self.assertEqual(list_values(block(pull_request, "branches", 4)), ["baseline-no-structures"])
        self.assertEqual(
            list_values(block(pull_request, "types", 4)),
            ["opened", "synchronize", "reopened", "ready_for_review"],
        )
        self.assertNotRegex(self.workflow, r"(?m)^\s*(?:paths|paths-ignore|if):")
        self.assertIn("    name: CSC preflight / validate\n", self.workflow)
        self.assertNotIn("workflow_dispatch", self.workflow)

    def test_one_short_hosted_job_with_read_only_permissions(self):
        self.assertEqual(block(self.workflow, "permissions").strip(), "contents: read")
        jobs = block(self.workflow, "jobs")
        self.assertEqual(re.findall(r"^  ([a-z_]+):$", jobs, re.MULTILINE), ["validate"])
        self.assertIn("    runs-on: ubuntu-24.04\n", jobs)
        self.assertIn("    timeout-minutes: 5\n", jobs)
        self.assertNotRegex(self.workflow, r"(?m)^\s*(?:environment|secrets|strategy|needs|continue-on-error):")
        self.assertNotIn("secrets.", self.workflow)
        self.assertNotIn("pull_request_target", self.workflow)

    def test_concurrency_is_specific_to_each_pull_request(self):
        concurrency = block(self.workflow, "concurrency")
        self.assertIn(
            "  group: csc-preflight-${{ github.event.pull_request.number }}",
            concurrency,
        )
        self.assertIn("  cancel-in-progress: true", concurrency)

    def test_checkout_is_verified_pinned_and_does_not_persist_credentials(self):
        actions = re.findall(r"^\s*uses: (\S+)", self.workflow, re.MULTILINE)
        self.assertEqual(actions, ["actions/checkout@" + CHECKOUT_SHA])
        self.assertRegex(CHECKOUT_SHA, r"^[0-9a-f]{40}$")
        for option in ("persist-credentials", "submodules", "lfs"):
            self.assertIn("          " + option + ": false\n", self.workflow)
        self.assertIn("          fetch-depth: 1\n", self.workflow)

    def test_only_fixed_local_preflight_commands_are_executed(self):
        commands = []
        lines = self.workflow.splitlines()
        for index, line in enumerate(lines):
            if line.startswith("        run: "):
                value = line[len("        run: ") :]
                if value == "|":
                    for following in lines[index + 1 :]:
                        if following.strip() and not following.startswith("          "):
                            break
                        if following.strip():
                            commands.append(following.strip())
                else:
                    commands.append(value)
        self.assertEqual(commands, [
            "/usr/bin/python3.12 --version",
            '/usr/bin/python3.12 -I -B -m venv "$RUNNER_TEMP/csc-preflight-venv"',
            'printf \'%s\\n\' "$RUNNER_TEMP/csc-preflight-venv/bin" >> "$GITHUB_PATH"',
            "python3 -I -B -m pip --isolated install --require-hashes --only-binary=:all: "
            "--no-input --disable-pip-version-check --retries 0 --timeout 30 "
            "--requirement automation/csc/requirements-preflight.lock",
            "python3 -I -B automation/csc/validate_manifest.py --schemas-only",
            "python3 -I -B automation/csc/tests/run_tests.py",
        ])
        self.assertFalse(any("${{" in command for command in commands))
        self.assertNotRegex("\n".join(commands), r"\b(?:ssh|scp|sftp|sbatch|srun|salloc|Rscript|gh|curl|wget)\b")


if __name__ == "__main__":
    unittest.main()
