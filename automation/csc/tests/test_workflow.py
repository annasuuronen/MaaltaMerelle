"""Static Actions isolation contracts; this module never starts a workflow.

The legacy workflow hashes pin the approved phase-1 baseline, feee323. Any
intentional future revision needs an explicit review of this preservation test.
Only the narrow YAML structures used by these workflows are read; no YAML
loader, subprocess, network connection or hydrology execution is required.
"""

import ast
import fnmatch
import hashlib
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"
PREFLIGHT = WORKFLOWS / "csc-preflight.yml"
CHECKOUT_SHA = "11bd71901bbe5b1630ceea73d27597364c9af683"
# Verified using read-only official refs/tags/v4.2.2 before implementation.
LEGACY_SHA256 = {
    "audit-02d8-schema.yml": "68dc453f6ed386321245d9bbe79b4d246cf628e2cebe988576ee96b51ccc0949",
    "audit-natural-evidence.yml": "b06e33ecc9d38420686d4c41183acd545478597bc784324cfe1f877fe2c667ca",
    "audit-partial-gradient.yml": "01ce77013293c4c25cf4c053fb6cffbf4d26344fd7e6b3b655b71a3e86e0d60c",
    "audit-r-source-graph.yml": "b1b60c145fa7cd53537f0e6b2fdeaad7da5803349b88642e8c3102d2807fd421",
    "audit-r-syntax.yml": "b4ccde01556cdbf538b49a9d64d0c20337af5dd1e6616ecff7cf1d2992be62cb",
    "audit-validation-fixtures.yml": "fd632eb904399eaf03fd486e9b7a2dae156294d46fa3722ffd0fa94f462455f2",
    "audit-workflow-safety.yml": "8cf116ece3b318fcde61e9f5100fd6691e071ae3a5cc48afacc9b8a4569943be",
    "continue-validation-gradient.yml": "bcd3a66f00148b61d24efbf711cf6d96d8403b9678a3273c6bf64cb29e1e1b84",
    "retry-hydrology-infra.yml": "9fa94a7b5984d8fa9bdd5f2ec9c3824e1bcb075229511c417626080b6027a361",
    "test-low-transfer.yml": "881e754bd16ea29da88189be07676929f05a452a86bdc69a07b70dbfd719151a",
    "test-moderate-transfer.yml": "90473d93fc8bda0f0b15e9ab1b87811a10bc39c3b99a3dc43891f47361fe2178",
    "test-natural-reference.yml": "8d26fb2f63f362af3d63513ee37ba6fe694f95b298f175ce52bda635719366c4",
    "test-portability-matrix.yml": "fce5f59f936ba6205493cf7603a79ed5fc423055fbf1c8c620182014b85372b3",
    "test-sulku-11.yml": "e945c699f803371515d85a67777de0a5966a9b8a74a3af5268afd85fb7378aaa",
    "verify-low-coastline.yml": "70006588da739b89582e75680635e7edb65f14478e97b2f59380573431f0a4b6",
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


class WorkflowIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = PREFLIGHT.read_text(encoding="utf-8")

    def test_all_fifteen_legacy_workflows_remain_byte_identical(self):
        files = {path.name for path in WORKFLOWS.iterdir() if path.is_file()}
        self.assertEqual(files, set(LEGACY_SHA256) | {PREFLIGHT.name})
        for filename, expected in LEGACY_SHA256.items():
            with self.subTest(workflow=filename):
                self.assertEqual(
                    hashlib.sha256((WORKFLOWS / filename).read_bytes()).hexdigest(),
                    expected,
                )

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
        push_workflows = 0
        for filename in LEGACY_SHA256:
            source = (WORKFLOWS / filename).read_text(encoding="utf-8")
            push = block(block(source, "on") or "", "push", 2)
            if push is None:
                continue
            push_workflows += 1
            self.assertEqual(list_values(block(push, "branches", 4)), ["baseline-no-structures"])
            patterns = list_values(block(push, "paths", 4))
            self.assertTrue(patterns, "an unrestricted legacy push trigger is unsafe")
            for path in paths:
                with self.subTest(workflow=filename, path=path):
                    self.assertFalse(path_matches(path, patterns))
        self.assertEqual(push_workflows, 14)

    def test_no_legacy_workflow_has_a_pull_request_trigger(self):
        for filename in LEGACY_SHA256:
            with self.subTest(workflow=filename):
                source = (WORKFLOWS / filename).read_text(encoding="utf-8")
                events = block(source, "on") or ""
                self.assertNotRegex(events, r"(?m)^  pull_request(?:_target)?:")

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
