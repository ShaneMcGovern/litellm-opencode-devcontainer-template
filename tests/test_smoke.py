"""Tests for the entry point."""

import pytest

from main import main


def test_main_prints_greeting(capsys: pytest.CaptureFixture[str]) -> None:
    main()
    assert "litellm-opencode-devcontainer-template" in capsys.readouterr().out
