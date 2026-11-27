"""Check that the OpenCode and LiteLLM settings agree with each other.

CI never builds the container or runs OpenCode, so a mismatch between these
files would otherwise show up only at run time, inside a session.
"""

import json
import re
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).parent.parent
LITELLM = ROOT / ".devcontainer" / "litellm.yaml"
COMPOSE = ROOT / ".devcontainer" / "compose.yaml"
OPENCODE = ROOT / "opencode.json"


def _litellm() -> dict[str, Any]:
    config: dict[str, Any] = yaml.safe_load(LITELLM.read_text(encoding="utf-8"))
    return config


def _opencode() -> dict[str, Any]:
    config: dict[str, Any] = json.loads(OPENCODE.read_text(encoding="utf-8"))
    return config


def _litellm_models() -> set[str]:
    return {entry["model_name"] for entry in _litellm()["model_list"]}


def _opencode_models() -> set[str]:
    return set(_opencode()["provider"]["litellm"]["models"])


def test_both_files_list_the_same_models() -> None:
    # A model only in opencode.json shows up in /models and then fails every
    # request with "Invalid model name". One only in litellm.yaml can't be
    # picked at all.
    assert _opencode_models() == _litellm_models()


def test_the_default_model_exists() -> None:
    provider, _, name = _opencode()["model"].partition("/")
    assert provider == "litellm"
    assert name in _litellm_models()


def test_opencode_talks_only_to_the_proxy() -> None:
    config = _opencode()
    assert config["enabled_providers"] == ["litellm"]
    assert config["share"] == "disabled"


def test_every_fallback_names_a_real_model() -> None:
    models = _litellm_models()
    for entry in _litellm()["router_settings"]["fallbacks"]:
        for source, targets in entry.items():
            assert source in models, f"fallback from unknown model {source!r}"
            unknown = set(targets) - models
            assert not unknown, f"{source} falls back to unknown {sorted(unknown)}"


def test_every_key_reaches_the_container() -> None:
    # compose.yaml passes only the variables it lists, so a key that is in
    # .env but missing there never reaches LiteLLM.
    compose = yaml.safe_load(COMPOSE.read_text(encoding="utf-8"))
    passed = {
        item.split("=", 1)[0] for item in compose["services"]["app"]["environment"]
    }
    used = set(re.findall(r"os\.environ/(\w+)", LITELLM.read_text(encoding="utf-8")))
    assert used, "litellm.yaml reads no environment variables"
    assert used <= passed, f"not passed by compose.yaml: {sorted(used - passed)}"


def test_claude_model_names_keep_prompt_caching() -> None:
    # OpenCode adds Anthropic's cache markers only when the model name
    # contains "claude" or "anthropic". Without them, every request pays full
    # price for the whole conversation.
    for entry in _litellm()["model_list"]:
        if entry["litellm_params"]["model"].startswith("anthropic/"):
            name = entry["model_name"]
            assert "claude" in name or "anthropic" in name, name
