import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "monsterasp_package.py"
WEB_CONFIG = Path(__file__).resolve().parents[3] / "src" / "Zaghlol.Api" / "web.config"
SENTINEL = 'p@ss"<&>word'


def run(*args):
    return subprocess.run([sys.executable, "-I", str(SCRIPT), *args], capture_output=True, text=True)


WORKFLOW = Path(__file__).resolve().parents[4] / ".github" / "workflows" / "backend-deploy-monsterasp.yml"


class WorkflowTests(unittest.TestCase):
    def test_migration_step_runs_as_production_with_the_database_ca(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        start = text.index("- name: Apply database migrations")
        step = text[start:text.index("\n      - name:", start + 10)]
        self.assertIn("Database__CaCertificatePem: ${{ secrets.BACKEND_DATABASE_CA_PEM }}", step)
        self.assertIn("DOTNET_ENVIRONMENT: Production", step)
        self.assertNotIn("echo", step)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "pkg"
        self.dir.mkdir()
        (self.dir / "web.config").write_text(WEB_CONFIG.read_text(encoding="utf-8-sig"), encoding="utf-8")
        self.settings = Path(self.tmp.name) / "settings.env"

    def tearDown(self):
        self.tmp.cleanup()

    def test_committed_template_passes_check(self):
        self.assertEqual(run("check", str(self.dir)).returncode, 0)

    def test_template_pools_fit_two_overlapping_processes_in_the_aiven_budget(self):
        # FU-281: an IIS overlapped recycle holds two processes' pools at once. Aiven free plan: 20 connections, 6 reserved.
        node = ET.parse(self.dir / "web.config").getroot().find(".//aspNetCore")
        pools = {v.get("name"): int(v.get("value")) for v in node.findall("environmentVariables/environmentVariable")
                 if v.get("name", "").startswith("Database__MaxPoolSize__")}
        self.assertEqual(set(pools), {"Database__MaxPoolSize__App", "Database__MaxPoolSize__Admin", "Database__MaxPoolSize__Worker"})
        readiness = 1  # fixed in code
        migrator = 2   # only while a deploy runs
        per_process = sum(pools.values()) + readiness
        self.assertLessEqual(2 * per_process + migrator, 14 - 2)  # keeps the 2 headroom for operator psql / pg_dump

    def test_check_rejects_unlisted_environment_variable_and_private_key(self):
        text = (self.dir / "web.config").read_text(encoding="utf-8")
        (self.dir / "web.config").write_text(
            text.replace("</environmentVariables>", '<environmentVariable name="ConnectionStrings__App" value="x" /></environmentVariables>'),
            encoding="utf-8")
        self.assertNotEqual(run("check", str(self.dir)).returncode, 0)
        (self.dir / "web.config").write_text(text, encoding="utf-8")
        (self.dir / "appsettings.json").write_text('{"k":"-----BEGIN PRIVATE KEY-----"}', encoding="utf-8")
        self.assertNotEqual(run("check", str(self.dir)).returncode, 0)

    def test_check_rejects_stdout_logging_and_outofprocess(self):
        text = (self.dir / "web.config").read_text(encoding="utf-8")
        (self.dir / "web.config").write_text(text.replace('stdoutLogEnabled="false"', 'stdoutLogEnabled="true"'), encoding="utf-8")
        self.assertNotEqual(run("check", str(self.dir)).returncode, 0)

    def test_render_escapes_values_and_prints_none(self):
        self.settings.write_text(f"# comment\nConnectionStrings__App=Host=h;Password={SENTINEL}\nHosting__EmbeddedWorkers=false\n", encoding="utf-8")
        result = run("render", str(self.dir), str(self.settings))
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("p@ss", result.stdout + result.stderr)
        out = (self.dir / "web.config").read_text(encoding="utf-8")
        self.assertIn("&quot;&lt;&amp;&gt;word", out)
        self.assertIn('name="Hosting__EmbeddedWorkers" value="false"', out)
        self.assertEqual(out.count('name="Hosting__EmbeddedWorkers"'), 1)

    def test_render_rejects_bad_lines_without_echoing_them(self):
        for body in ("no-equals-sign-secret-value\n", "A=1\nA=2\n", "bad name=1\n", "DOTNET_EnableDiagnostics=1\n",
                     "ASPNETCORE_ENVIRONMENT=Development\n", "dotnet_environment=Development\n",
                     "Database__AllowInsecureTransport=true\n", "Foo__AllowInsecureBar=1\n"):
            self.settings.write_text(body, encoding="utf-8")
            result = run("render", str(self.dir), str(self.settings))
            self.assertNotEqual(result.returncode, 0, body)
            self.assertNotIn("secret-value", result.stderr)


if __name__ == "__main__":
    unittest.main()
