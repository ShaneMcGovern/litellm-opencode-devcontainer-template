"""Entry point. Run it with `python -m main`, with `src` on PYTHONPATH.

The work is in `main`, not at module scope, so a test can import the
module without running it.
"""


def main() -> None:
    print("Hello from litellm-opencode-devcontainer-template.")


if __name__ == "__main__":
    main()
