#!/usr/bin/env python3
"""
Generate per-host Hub secrets and render the Jinja2 config templates.

The Windows install previously copied static seed files from
windows/seed/ that had hardcoded dev passwords committed to the public
repo. This script generates random passwords + HANA token secrets,
persists them to a host-local YAML file, and renders the same Jinja2
templates the Linux/macOS install uses (debos/overlays/ansible/templates/).

Mirrors debos/overlays/ansible/generate-secrets.yaml.

Idempotent — re-runs reuse the existing secrets file. Pass --rotate
to force fresh secret generation; note that RabbitMQ persists its
user database in its volume on first launch, so rotating secrets
after the stack has come up at least once requires
`docker compose down -v` to take effect.
"""
import argparse
import secrets as pysecrets
import string
import sys
from pathlib import Path

try:
    import yaml
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ImportError as exc:
    sys.stderr.write(f"ERROR: missing Python dependency: {exc.name}\n")
    sys.stderr.write("Install with:\n")
    sys.stderr.write("    python -m pip install jinja2 PyYAML\n")
    sys.exit(2)


# Service users referenced by rabbitmq.json.j2 / diana.yaml.j2 / neon.yaml.j2.
# Source: union of every `{{ users.X.password }}` across those three files.
SERVICE_USERS = (
    "neon_core",
    "neon_api",
    "neon_coupons",
    "neon_email",
    "neon_script_parser",
    "neon_llm_chatgpt",
    "neon_llm_fastchat",
    "neon_llm_vllm",
    "neon_metrics",
    "chat_observer",
    "neon_bot_submind",
    "neon_llm_submind",
    "neon_bot_facilitator",
    "neon_users_service",
)

# HANA-side secrets referenced by diana.yaml.j2 (and node_pw by neon.yaml.j2).
HANA_SECRETS = ("access_token_secret", "refresh_token_secret", "node_pw")

# Renders are tuples of (template name in --templates-dir, output path
# relative to --output-dir). All three are rendered every run, even when
# secrets are reused, so editing a template propagates without --rotate.
RENDERS = (
    ("rabbitmq.json.j2", "xdg/config/rabbitmq/rabbitmq.json"),
    ("diana.yaml.j2",    "xdg/config/neon/diana.yaml"),
    ("neon.yaml.j2",     "xdg/config/neon/neon.yaml"),
)

ALPHABET = string.ascii_letters + string.digits


def random_token(length):
    return "".join(pysecrets.choice(ALPHABET) for _ in range(length))


def build_secrets():
    """Mint a fresh set of service-user + HANA secrets."""
    return {
        "users": {u: {"password": random_token(32)} for u in SERVICE_USERS},
        "hana":  {k: random_token(64) for k in HANA_SECRETS},
    }


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
    )
    parser.add_argument("--hostname", required=True,
                        help="NEON_HOSTNAME, used as Jinja's `common_name`")
    parser.add_argument("--templates-dir", required=True,
                        help="directory containing the .j2 templates")
    parser.add_argument("--secrets-file", required=True,
                        help="where to persist generated secrets (reused on re-runs)")
    parser.add_argument("--output-dir", required=True,
                        help="NEON_HOME root; rendered files land under xdg/config/...")
    parser.add_argument("--rotate", action="store_true",
                        help="regenerate secrets even if --secrets-file already exists")
    args = parser.parse_args()

    secrets_path = Path(args.secrets_file)
    if secrets_path.exists() and not args.rotate:
        data = yaml.safe_load(secrets_path.read_text(encoding="utf-8"))
        print(f"reusing existing secrets from {secrets_path}")
    else:
        data = build_secrets()
        secrets_path.parent.mkdir(parents=True, exist_ok=True)
        secrets_path.write_text(
            yaml.safe_dump(data, sort_keys=False),
            encoding="utf-8",
        )
        action = "rotated" if secrets_path.exists() and args.rotate else "generated"
        print(f"{action} new secrets at {secrets_path}")

    env = Environment(
        loader=FileSystemLoader(args.templates_dir),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
    )
    context = {**data, "common_name": args.hostname}

    out_root = Path(args.output_dir)
    for template_name, rel_path in RENDERS:
        rendered = env.get_template(template_name).render(**context)
        dest = out_root / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(rendered, encoding="utf-8")
        print(f"rendered {template_name} -> {dest}")


if __name__ == "__main__":
    main()
