#!/usr/bin/env python3
"""Package tooling for the MonsterASP.NET deploy (T-206). Standard library only; run as `python3 -I monsterasp_package.py ...`.

  check  <publish-dir>                  the package builds a safe web.config: in-process, stdout logging off, only the allow-listed
                                        non-secret environment variables, no secrets or private keys anywhere in the files.
  render <publish-dir> <settings-file>  add the deploy-time settings (one NAME=value per line, from the environment secret) to the
                                        web.config <environmentVariables>. Values are XML-escaped and never printed; errors name
                                        a line number only.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Names that may already be in the committed web.config template (their values are public).
TEMPLATE_ALLOWED = {
    "ASPNETCORE_ENVIRONMENT",
    "Hosting__EmbeddedWorkers",
    "ForwardedHeaders__NoProxy",
    "DOTNET_EnableDiagnostics",
}
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(__[A-Za-z0-9_-]+)*$")
# Settings that must never be supplied at deploy time on this profile.
FORBIDDEN = {
    "ASPNETCORE_HOSTINGMODEL",
    "DOTNET_DbgEnableMiniDump",
    "DOTNET_EnableDiagnostics",
    "ASPNETCORE_DETAILEDERRORS",
    "Dev__FakeStores",
}
# The environment name is fixed by the committed template, and no guard-relaxing switch (`*__AllowInsecure*`) may be set at deploy time.
FORBIDDEN_UPPER = {"ASPNETCORE_ENVIRONMENT", "DOTNET_ENVIRONMENT"}
SECRET_PATTERNS = [
    re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(rb"(?i)\bpassword\s*=\s*[^;\s\"<]{3,}"),
    re.compile(rb"(?i)\bpwd\s*=\s*[^;\s\"<]{3,}"),
]
TEXT_SUFFIXES = {".json", ".config", ".xml", ".txt", ".pem", ".key", ".env", ".yml", ".yaml", ".pubxml"}
NS_FREE = "aspNetCore"


def _fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def _load(directory: Path):
    path = directory / "web.config"
    if not path.is_file():
        _fail("web.config is missing from the package")
    tree = ET.parse(path)
    node = tree.getroot().find(f".//{NS_FREE}")
    if node is None:
        _fail("web.config has no aspNetCore element")
    return tree, node, path


def check(directory: Path) -> None:
    _, node, _ = _load(directory)
    if node.get("hostingModel", "").lower() != "inprocess":
        _fail("aspNetCore hostingModel must be inprocess")
    if node.get("stdoutLogEnabled", "").lower() != "false":
        _fail("aspNetCore stdoutLogEnabled must be false")
    variables = node.findall("environmentVariables/environmentVariable")
    for variable in variables:
        if variable.get("name") not in TEMPLATE_ALLOWED:
            _fail(f"environment variable {variable.get('name')!r} is not allow-listed in the committed template")
    for file in sorted(p for p in directory.rglob("*") if p.is_file()):
        if file.suffix.lower() not in TEXT_SUFFIXES:
            continue
        data = file.read_bytes()
        for pattern in SECRET_PATTERNS:
            if pattern.search(data):
                _fail(f"{file.relative_to(directory)} looks like it holds a secret")
    print("package check ok")


def parse_settings(text: str) -> dict[str, str]:
    settings: dict[str, str] = {}
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        name, separator, value = line.partition("=")
        name = name.strip()
        if not separator or not NAME.match(name):
            _fail(f"settings line {number}: expected NAME=value with a valid name")
        if name in FORBIDDEN or name.upper() in FORBIDDEN_UPPER or "__ALLOWINSECURE" in name.upper():
            _fail(f"settings line {number}: this setting may not be supplied at deploy time")
        if name in settings:
            _fail(f"settings line {number}: duplicate name")
        if any(ord(c) < 32 for c in value):
            _fail(f"settings line {number}: control characters are not allowed in a value")
        settings[name] = value
    return settings


def render(directory: Path, settings_file: Path) -> None:
    settings = parse_settings(settings_file.read_text(encoding="utf-8"))
    tree, node, path = _load(directory)
    container = node.find("environmentVariables")
    if container is None:
        container = ET.SubElement(node, "environmentVariables")
    existing = {v.get("name"): v for v in container.findall("environmentVariable")}
    for name, value in settings.items():
        if name in existing:
            existing[name].set("value", value)
        else:
            ET.SubElement(container, "environmentVariable", {"name": name, "value": value})
    ET.indent(tree)
    tree.write(path, encoding="utf-8", xml_declaration=True)
    print(f"rendered {len(settings)} settings into web.config (values not shown)")


def main(argv: list[str]) -> None:
    if len(argv) == 3 and argv[1] == "check":
        check(Path(argv[2]))
    elif len(argv) == 4 and argv[1] == "render":
        render(Path(argv[2]), Path(argv[3]))
    else:
        _fail("usage: monsterasp_package.py check <dir> | render <dir> <settings-file>")


if __name__ == "__main__":
    main(sys.argv)
