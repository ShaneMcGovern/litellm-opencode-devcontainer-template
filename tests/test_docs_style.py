"""Check the doc rules a test can catch. CONTRIBUTING.md has the rest."""

import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent

DOCUMENTS = ("README.md", "CONTRIBUTING.md")


@pytest.mark.parametrize("name", DOCUMENTS)
def test_document_is_plain_ascii(name: str) -> None:
    text = (ROOT / name).read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), start=1):
        bad = sorted({character for character in line if ord(character) > 127})
        assert not bad, f"{name}:{number} has non-ASCII characters {bad!r}"


@pytest.mark.parametrize("name", DOCUMENTS)
def test_document_does_not_hardcode_the_release_version(name: str) -> None:
    # A release never rewrites these docs.
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    version = pyproject["project"]["version"]
    text = (ROOT / name).read_text(encoding="utf-8")
    assert version not in text, f"{name} hardcodes release version {version}"
