"""Check that each tool version pinned in more than one file matches.

Dependabot bumps the uv and Python image tags in the Dockerfile, but none
of the other pins, so a bump that leaves them behind fails here until they
match.
"""

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent
DOCKERFILE = (ROOT / ".devcontainer" / "Dockerfile").read_text(encoding="utf-8")


def _tag(image: str) -> str:
    match = re.search(rf"^FROM {re.escape(image)}:([^@\s]+)", DOCKERFILE, re.M)
    assert match, f"no FROM line for {image}"
    return match.group(1)


def _read(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def test_uv_matches_the_image() -> None:
    uv = _tag("ghcr.io/astral-sh/uv")
    # Each setup-uv step names its uv. required-version in pyproject.toml would
    # also stop Dependabot's own uv from running the weekly uv updates.
    pinned = re.compile(r"uses: astral-sh/setup-uv@.*\n\s+with:\n\s+version: \"(\S+)\"")
    for workflow in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
        text = workflow.read_text(encoding="utf-8")
        steps = text.count("uses: astral-sh/setup-uv@")
        pins = pinned.findall(text)
        assert pins == [uv] * steps, f"{workflow.name}: setup-uv needs version {uv}"
    hooks = _read(".pre-commit-config.yaml")
    hook = re.search(r"astral-sh/uv-pre-commit\n\s+rev: (\S+)", hooks)
    assert hook, "no uv-pre-commit hook"
    assert hook.group(1) == uv


def test_python_matches_the_image() -> None:
    python = _tag("python").split("-")[0]
    assert _read(".python-version").strip() == python
    assert f"python_version: {python}\n" in _read(".copier-answers.yml")
    readme = _read("README.md")
    assert f"[![Python {python}]" in readme
    assert f"badge/python-{python}-" in readme
