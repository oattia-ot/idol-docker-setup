#!/usr/bin/env python3
"""
IDOL Community - Create Users & Roles Script
============================================
All actions (reads and writes) go to the ACI port over HTTPS.
Correct action name: RoleAddUserToRole (singular).

Configuration (first match wins for each setting):
  1. Command-line flags
  2. Environment variables
  3. Interactive prompt (skipped with --yes / COMMUNITY_YES=1)

Examples
--------
  # Standalone against a host IP, skip prompts, don't verify TLS
  python create-users-roles.py --host 172.25.125.123 --port 9033 --insecure -y

  # With an explicit CA bundle
  python create-users-roles.py --host 172.25.125.123 --port 9033 \\
      --cert /path/to/ca-chain.cert.pem -y

  # Env vars (same as before)
  COMMUNITY_HOST=172.25.125.123 COMMUNITY_PORT=9033 \\
  COMMUNITY_INSECURE=1 COMMUNITY_YES=1 python create-users-roles.py
"""

from __future__ import annotations

import argparse
import os
import sys
import warnings
from pathlib import Path

import requests
import xml.etree.ElementTree as ET
from xml.dom import minidom
from requests.exceptions import SSLError, ConnectionError as RequestsConnectionError

try:
    import urllib3
except ImportError:
    urllib3 = None


# ---------------------------------------------------------------------------
# Defaults / candidate cert locations
# ---------------------------------------------------------------------------

DEFAULT_HOST = "idol-docker-host"
DEFAULT_PORT = "9033"
DEFAULT_CERT_RELATIVE = (
    "./idol-docker-setup/idol-containers-toolkit/data-admin/ssl/"
    "intermediate/certs/ca-chain.cert.pem"
)

CERT_CANDIDATES = [
    os.environ.get("COMMUNITY_CERT", ""),
    DEFAULT_CERT_RELATIVE,
    "/ssl/certs/ca-chain.cert.pem",
    "/ssl/intermediate/certs/ca-chain.cert.pem",
    "./ssl/certs/ca-chain.cert.pem",
    "./certs/ca-chain.cert.pem",
    "./ca-chain.cert.pem",
    str(Path.home() / "idol-docker-setup/idol-containers-toolkit/"
        "data-admin/ssl/intermediate/certs/ca-chain.cert.pem"),
]


def _truthy(val: str | None) -> bool:
    return str(val or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def _existing_file(path: str | None) -> str | None:
    if not path:
        return None
    p = Path(path).expanduser()
    if p.is_file():
        return str(p.resolve())
    # Also try relative to this script's directory (standalone from any CWD)
    script_dir = Path(__file__).resolve().parent
    alt = (script_dir / path).resolve()
    if alt.is_file():
        return str(alt)
    return None


def find_cert(explicit: str | None) -> str | None:
    """Return an existing cert path, or None if none of the candidates exist."""
    checked = []
    for raw in [explicit or "", *CERT_CANDIDATES]:
        if not raw or raw in checked:
            continue
        checked.append(raw)
        found = _existing_file(raw)
        if found:
            return found
    return None


def prompt_if_unset(env_var, description, hints, default, cli_value=None, non_interactive=False):
    """
    Resolve a setting from: CLI flag -> env var -> prompt -> default.
    In non-interactive mode the prompt is skipped and the default is used.
    """
    if cli_value not in (None, ""):
        print(f"{env_var}")
        print(f"  [FROM CLI] {cli_value}")
        print()
        return cli_value

    env_val = os.environ.get(env_var)
    if env_val:
        print(f"{env_var}")
        print(f"  [FROM ENV] {env_val}")
        print()
        return env_val

    if non_interactive:
        print(f"{env_var}")
        print(f"  [DEFAULT] {default}")
        print()
        return default

    print(f"{env_var}  {description}")
    for hint in hints:
        print(f"  {hint}")
    try:
        val = input(f"  > [{default}]: ").strip()
    except EOFError:
        val = ""
    print()
    return val or default


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Create IDOL Community users and roles over the ACI HTTPS port.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Env vars: COMMUNITY_HOST, COMMUNITY_PORT, COMMUNITY_CERT,\n"
            "          COMMUNITY_INSECURE=1, COMMUNITY_YES=1,\n"
            "          EXTRA_IP_SANS_ENV, IDOL_NET_HOST_IP"
        ),
    )
    p.add_argument("--host", dest="host", help="Community host / IP / DNS name")
    p.add_argument("--port", dest="port", help="Community ACI port (default: 9033)")
    p.add_argument("--cert", dest="cert", help="Path to CA chain PEM used to verify TLS")
    p.add_argument(
        "--insecure",
        action="store_true",
        help="Do not verify TLS (use when the CA bundle is not available). "
             "Equivalent to COMMUNITY_INSECURE=1",
    )
    p.add_argument(
        "-y", "--yes",
        action="store_true",
        help="Non-interactive: skip prompts and the Proceed? confirmation. "
             "Equivalent to COMMUNITY_YES=1",
    )
    p.add_argument(
        "--scheme",
        choices=("https", "http"),
        default="https",
        help="URL scheme (default: https)",
    )
    return p.parse_args(argv)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BENIGN_ERRORS = {"Role Exists", "User Exists"}


def pretty_print_xml(xml_string):
    try:
        root = ET.fromstring(xml_string)
        rough_string = ET.tostring(root, "utf-8")
        reparsed = minidom.parseString(rough_string)
        return reparsed.toprettyxml(indent="    ")
    except Exception:
        return xml_string


def parse_error_description(xml_string):
    try:
        root = ET.fromstring(xml_string)
        desc = root.find(".//{http://schemas.autonomy.com/aci/}errordescription")
        if desc is None:
            desc = root.find(".//errordescription")
        return desc.text.strip() if desc is not None and desc.text else ""
    except Exception:
        return ""


def call_community(base_url, verify, action, params, label):
    payload = {"action": action, **params}
    print(f"[{label}]")
    try:
        response = requests.get(base_url, params=payload, verify=verify, timeout=10)
        response.raise_for_status()
        if "<response>ERROR</response>" in response.text:
            desc = parse_error_description(response.text)
            if any(b in desc for b in BENIGN_ERRORS):
                print("  OK (already exists — skipping)")
            else:
                print(f"  !! COMMUNITY ERROR: {desc}")
                print(pretty_print_xml(response.text))
        else:
            print("  OK")
    except RequestsConnectionError as e:
        print(f"  !! CONNECTION ERROR: {e}")
        print(f"     -> Community not reachable at {base_url}")
        print("     -> On the host: docker ps | grep community")
    except SSLError as e:
        print(f"  !! SSL ERROR: {e}")
        print("     -> Pass a valid --cert / COMMUNITY_CERT, or use --insecure")
    except OSError as e:
        # requests raises OSError when verify= points at a missing file
        print(f"  !! TLS BUNDLE ERROR: {e}")
        print("     -> Pass a valid --cert / COMMUNITY_CERT, or use --insecure")
    except Exception as e:
        print(f"  !! UNEXPECTED ERROR: {type(e).__name__}: {e}")


def create_user(base_url, verify, username, password):
    # Official parameter names are UserName / Password; ACI is case-insensitive
    # but we send both canonical names to be safe across versions.
    call_community(
        base_url, verify, "UserAdd",
        {"UserName": username, "username": username, "Password": password, "password": password},
        f"Create user '{username}'",
    )


def create_role(base_url, verify, rolename):
    call_community(
        base_url, verify, "RoleAdd",
        {"RoleName": rolename},
        f"Create role '{rolename}'",
    )


def add_user_to_role(base_url, verify, username, rolename):
    # Singular: RoleAddUserToRole — correct for this version of IDOL Community
    call_community(
        base_url, verify, "RoleAddUserToRole",
        {"RoleName": rolename, "UserName": username},
        f"Assign '{username}' -> '{rolename}'",
    )


def verify_user_roles(base_url, verify, username):
    print(f"\n[Verify roles for '{username}']")
    try:
        response = requests.get(
            base_url,
            params={"action": "UserRead", "UserName": username, "RoleList": "true"},
            verify=verify,
            timeout=10,
        )
        response.raise_for_status()
        print(pretty_print_xml(response.text))
    except Exception as e:
        print(f"  !! ERROR: {e}")


def configure(args):
    non_interactive = bool(args.yes or _truthy(os.environ.get("COMMUNITY_YES")))
    insecure_flag = bool(args.insecure or _truthy(os.environ.get("COMMUNITY_INSECURE")))

    print()
    print("=" * 60)
    print("  IDOL Community - User & Role Setup")
    print("=" * 60)
    print()
    print("Resolution order: CLI flag → env var → prompt → default.")
    if non_interactive:
        print("Non-interactive mode: prompts are skipped.")
    print()

    # Auto-select COMMUNITY_HOST from EXTRA_IP_SANS_ENV / IDOL_NET_HOST_IP
    # only if COMMUNITY_HOST is not already set and --host was not given.
    if not args.host and not os.environ.get("COMMUNITY_HOST"):
        extra = os.environ.get("EXTRA_IP_SANS_ENV")
        host_ip = os.environ.get("IDOL_NET_HOST_IP")
        if extra and host_ip and extra != host_ip:
            os.environ["COMMUNITY_HOST"] = extra
            print(f"COMMUNITY_HOST auto-set from EXTRA_IP_SANS_ENV → {extra}")
        elif host_ip:
            os.environ["COMMUNITY_HOST"] = host_ip
            print(f"COMMUNITY_HOST auto-set from IDOL_NET_HOST_IP → {host_ip}")
        print()

    host = prompt_if_unset(
        env_var="COMMUNITY_HOST",
        description="",
        hints=[
            "Inside a container on idol-demo-network : idol-dataadmin-community",
            "On the host machine                     : FQDN, IP, or idol-docker-host",
        ],
        default=DEFAULT_HOST,
        cli_value=args.host,
        non_interactive=non_interactive,
    )

    port = prompt_if_unset(
        env_var="COMMUNITY_PORT",
        description="(ACI port — all actions go here over HTTPS)",
        hints=[
            "Inside a container : 9033",
            "On the host        : check with 'docker ps | grep community'",
            "                     and use the mapped host port (e.g. 19033)",
        ],
        default=DEFAULT_PORT,
        cli_value=args.port,
        non_interactive=non_interactive,
    )

    cert_input = prompt_if_unset(
        env_var="COMMUNITY_CERT",
        description="(CA chain cert for Community's SSL; leave default if unknown)",
        hints=[
            "Usually at: <ssl-mount>/certs/ca-chain.cert.pem",
            f"Relative     : {DEFAULT_CERT_RELATIVE}",
            "In container : /ssl/certs/ca-chain.cert.pem",
            "Missing cert : use --insecure / COMMUNITY_INSECURE=1",
        ],
        default=DEFAULT_CERT_RELATIVE,
        cli_value=args.cert,
        non_interactive=non_interactive,
    )

    resolved_cert = find_cert(cert_input)
    if insecure_flag:
        verify = False
        cert_display = "(insecure — TLS verification DISABLED)"
        print("  !! COMMUNITY_INSECURE / --insecure set: TLS will not be verified.")
        print()
        if urllib3 is not None:
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        warnings.filterwarnings("ignore", message="Unverified HTTPS request")
    elif resolved_cert:
        verify = resolved_cert
        cert_display = resolved_cert
        if resolved_cert != cert_input:
            print(f"  Using discovered cert: {resolved_cert}")
            print()
    else:
        print(f"  !! WARNING: cert file not found at: {cert_input}")
        print("     No candidate CA bundle was found either.")
        if non_interactive:
            print("     Falling back to --insecure (TLS verification DISABLED).")
            print("     Pass --cert <path> to verify, or set --insecure explicitly.")
            print()
            verify = False
            cert_display = f"(NOT FOUND: {cert_input} — TLS verification DISABLED)"
            if urllib3 is not None:
                urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
            warnings.filterwarnings("ignore", message="Unverified HTTPS request")
        else:
            try:
                answer = input("     Continue without TLS verification? [y/N]: ").strip().lower()
            except EOFError:
                answer = "n"
            print()
            if answer in {"y", "yes"}:
                verify = False
                cert_display = f"(NOT FOUND: {cert_input} — TLS verification DISABLED)"
                if urllib3 is not None:
                    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
                warnings.filterwarnings("ignore", message="Unverified HTTPS request")
            else:
                print("Aborted. Provide a valid cert with --cert / COMMUNITY_CERT,")
                print("or rerun with --insecure.")
                sys.exit(1)

    scheme = args.scheme or "https"
    base_url = f"{scheme}://{host}:{port}"

    print("-" * 60)
    print(f"  Community URL : {base_url}")
    print(f"  Cert path     : {cert_display}")
    print(f"  TLS verify    : {verify if isinstance(verify, bool) else 'CA bundle'}")
    print("-" * 60)
    print()

    if non_interactive:
        print("Proceeding (--yes / COMMUNITY_YES).")
        print()
    else:
        try:
            confirm = input("Proceed? [Y/n]: ").strip().lower()
        except EOFError:
            confirm = "y"
        if confirm == "n":
            print("Aborted.")
            sys.exit(0)
        print()

    return base_url, verify


def run(base_url, verify):
    print("--- Creating roles ---")
    for role in ["FindBI", "FindUser", "FindAdmin", "AnswerBankUser",
                 "IDAUser", "ISOAdmin", "ISOUser", "everyone"]:
        create_role(base_url, verify, role)

    print("\n--- Creating users ---")
    create_user(base_url, verify, "admin", "admin")
    create_user(base_url, verify, "bank", "admin")

    print("\n--- Assigning roles: admin (full access) ---")
    for role in ["FindBI", "FindAdmin", "FindUser", "IDAUser", "AnswerBankUser"]:
        add_user_to_role(base_url, verify, "admin", role)

    print("\n--- Assigning roles: bank (standard user) ---")
    for role in ["FindUser", "IDAUser", "AnswerBankUser"]:
        add_user_to_role(base_url, verify, "bank", role)

    print("\n--- Verifying ---")
    verify_user_roles(base_url, verify, "admin")
    verify_user_roles(base_url, verify, "bank")

    print("\nDone.")


def main(argv=None):
    args = parse_args(argv)
    base_url, verify = configure(args)
    run(base_url, verify)


if __name__ == "__main__":
    main()