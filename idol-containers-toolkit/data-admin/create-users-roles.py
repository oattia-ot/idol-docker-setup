"""
IDOL Community - Create Users & Roles Script
============================================
All actions (reads and writes) go to the ACI port over HTTPS.
Correct action name: RoleAddUserToRole (singular).

If COMMUNITY_HOST, COMMUNITY_PORT, or COMMUNITY_CERT are already set
as environment variables, those values are used directly without prompting.
"""

import os
import requests
import xml.etree.ElementTree as ET
from xml.dom import minidom


def prompt_if_unset(env_var, description, hints, default):
    """
    Return the env var value if already set, otherwise prompt the user.
    Prints a [FROM ENV] notice when skipping the prompt.
    """
    env_val = os.environ.get(env_var)
    if env_val:
        print(f"{env_var}")
        print(f"  [FROM ENV] {env_val}")
        print()
        return env_val

    # Not set — show hints and prompt
    print(f"{env_var}  {description}")
    for hint in hints:
        print(f"  {hint}")
    val = input(f"  > [{default}]: ").strip()
    print()
    return val or default


# ---------------------------------------------------------------------------
# Interactive configuration (skipped per variable if env var is set)
# ---------------------------------------------------------------------------

print()
print("=" * 60)
print("  IDOL Community - User & Role Setup")
print("=" * 60)
print()
print("Variables already set as env vars will be used without prompting.")
print()

# Auto-select COMMUNITY_HOST from EXTRA_IP_SANS_ENV / IDOL_NET_HOST_IP
# only if COMMUNITY_HOST is not already set in the environment.
if not os.environ.get("COMMUNITY_HOST"):
    extra = os.environ.get("EXTRA_IP_SANS_ENV")
    host_ip = os.environ.get("IDOL_NET_HOST_IP")
    if extra and host_ip and extra != host_ip:
        os.environ["COMMUNITY_HOST"] = extra
        print(f"COMMUNITY_HOST auto-set from EXTRA_IP_SANS_ENV → {extra}")
    elif host_ip:
        os.environ["COMMUNITY_HOST"] = host_ip
        print(f"COMMUNITY_HOST auto-set from IDOL_NET_HOST_IP → {host_ip}")
    print()
    
COMMUNITY_HOST = prompt_if_unset(
    env_var="COMMUNITY_HOST",
    description="",
    hints=[
        "Inside a container on idol-demo-network : idol-dataadmin-community",
        "On the host machine                     : FQDN, IP, or idol-docker-host",
    ],
    default="idol-docker-host",
)

COMMUNITY_PORT = prompt_if_unset(
    env_var="COMMUNITY_PORT",
    description="(ACI port — all actions go here over HTTPS)",
    hints=[
        "Inside a container : 9033",
        "On the host        : check with 'docker ps | grep community'",
        "                     and use the mapped host port (e.g. 19033)",
    ],
    default="9033",
)

COMMUNITY_CERT = prompt_if_unset(
    env_var="COMMUNITY_CERT",
    description="(CA chain cert for Community's SSL)",
    hints=[
        "Usually at: <ssl-mount>/certs/ca-chain.cert.pem",
        "Relative     : ./idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem",
        "In container : /ssl/certs/ca-chain.cert.pem",
    ],
    default="./idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem",
)

if not os.path.isfile(COMMUNITY_CERT):
    print(f"  !! WARNING: cert file not found at: {COMMUNITY_CERT}")
    print("     Requests will fail with an SSL error if this is wrong.")
    print()

BASE_URL = f"https://{COMMUNITY_HOST}:{COMMUNITY_PORT}"

print("-" * 60)
print(f"  Community URL : {BASE_URL}")
print(f"  Cert path     : {COMMUNITY_CERT}")
print("-" * 60)
print()
_confirm = input("Proceed? [Y/n]: ").strip().lower()
if _confirm == "n":
    print("Aborted.")
    exit(0)
print()

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


def call_community(action, params, label):
    payload = {"action": action, **params}
    print(f"[{label}]")
    try:
        response = requests.get(BASE_URL, params=payload, verify=COMMUNITY_CERT, timeout=10)
        response.raise_for_status()
        if "<response>ERROR</response>" in response.text:
            desc = parse_error_description(response.text)
            if any(b in desc for b in BENIGN_ERRORS):
                print(f"  OK (already exists — skipping)")
            else:
                print(f"  !! COMMUNITY ERROR: {desc}")
                print(pretty_print_xml(response.text))
        else:
            print(f"  OK")
    except requests.exceptions.ConnectionError as e:
        print(f"  !! CONNECTION ERROR: {e}")
        print(f"     -> Community not reachable at {BASE_URL}")
        print(f"     -> On the host: docker ps | grep community")
    except requests.exceptions.SSLError as e:
        print(f"  !! SSL ERROR: {e}")
        print(f"     -> Check COMMUNITY_CERT path: {COMMUNITY_CERT}")
    except Exception as e:
        print(f"  !! UNEXPECTED ERROR: {e}")


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def create_user(username, password):
    call_community("UserAdd", {"username": username, "password": password}, f"Create user '{username}'")


def create_role(rolename):
    call_community("RoleAdd", {"RoleName": rolename}, f"Create role '{rolename}'")


def add_user_to_role(username, rolename):
    # Singular: RoleAddUserToRole — correct for this version of IDOL Community
    call_community("RoleAddUserToRole", {"RoleName": rolename, "UserName": username},
                   f"Assign '{username}' -> '{rolename}'")


def verify_user_roles(username):
    print(f"\n[Verify roles for '{username}']")
    try:
        response = requests.get(
            BASE_URL,
            params={"action": "UserRead", "UserName": username, "RoleList": "true"},
            verify=COMMUNITY_CERT,
            timeout=10
        )
        response.raise_for_status()
        print(pretty_print_xml(response.text))
    except Exception as e:
        print(f"  !! ERROR: {e}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

print("--- Creating roles ---")
for role in ["FindBI", "FindUser", "FindAdmin", "AnswerBankUser", "IDAUser", "ISOAdmin", "ISOUser", "everyone"]:
    create_role(role)

print("\n--- Creating users ---")
create_user("admin", "admin")
create_user("bank", "admin")

print("\n--- Assigning roles: admin (full access) ---")
for role in ["FindBI", "FindAdmin", "FindUser", "IDAUser", "AnswerBankUser"]:
    add_user_to_role("admin", role)

print("\n--- Assigning roles: bank (standard user) ---")
for role in ["FindUser", "IDAUser", "AnswerBankUser"]:
    add_user_to_role("bank", role)

print("\n--- Verifying ---")
verify_user_roles("admin")
verify_user_roles("bank")

print("\nDone.")
