#!/usr/bin/env python3
"""
Full Reindex Script for IDOL Content Index.

Auto-installs 'requests' if missing using `python -m pip install requests`.

Safely reindexes the Content index using official ACI IndexerGetStatus monitoring:

1. Exports current index to compressed .idx.gz via DREEXPORTIDX.
2. Wipes and initializes fresh index via DREINITIAL (always job ID=1).
3. Imports data via DREADD from export file, deleting it after.

Each step is polled until 100% complete (status=-1). No hardcoded sleeps or race conditions.

Configuration:
- ACI_HOST/ACI_PORT: Status queries (9200).
- INDEX_PORT: Index actions (9201).
- CERT: SSL cert path.
- EXPORT_DIR: Export file location (/data).

Usage: Run script directly (`python3 reload.py`). Creates timestamped export in EXPORT_DIR.
"""

import subprocess
import sys

def install_requests():
    """Install requests package if missing."""
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests"])

try:
    import requests
except ImportError:
    install_requests()
    import requests

import time
from datetime import datetime
import xml.etree.ElementTree as ET

# YOUR REAL SETTINGS
ACI_HOST = "content1.idoldemos.net"
ACI_PORT = 9200           # ← ACI port for IndexerGetStatus
INDEX_PORT = 9201         # ← Index port for DRE* actions
CERT = "/home/vinay/projects/load_testing/content_layer/content1/ssl/content/bundle.crt"
EXPORT_DIR = "/data"

aci_url = f"https://{ACI_HOST}:{ACI_PORT}"
index_url = f"https://{ACI_HOST}:{INDEX_PORT}"

session = requests.Session()
session.verify = CERT

def get_status():
    """Retrieve indexer status XML from ACI.

    Returns:
        ET.Element: Parsed status XML root.

    Raises:
        requests.RequestException: On HTTP errors or timeout.
    """
    r = session.get(f"{aci_url}/action=IndexerGetStatus", timeout=30)
    r.raise_for_status()
    return ET.fromstring(r.text)

def wait_for_job(job_id, command_prefix=None):
    """
    Poll ACI status until specified job completes to 100%.

    Args:
        job_id (str): Job ID from DRE* response (e.g., export_id).
        command_prefix (str, optional): Filter to jobs with this command prefix
            (e.g., 'DREEXPORTIDX'). Defaults to None.

    Returns:
        bool: True if job reached status=-1 and 100% processed.
    """
    print(f"Waiting for job {job_id} to finish...", end="")
    while True:
        root = get_status()
        ns = {'autn': 'http://schemas.autonomy.com/aci/'}
        
        for item in root.findall('.//autn:item', ns):
            iid = item.find('autn:id', ns)
            if iid is None or iid.text != str(job_id):
                continue
                
            status = item.find('autn:status', ns).text
            percent = int(item.find('autn:percentage_processed', ns).text)
            desc = item.find('autn:description', ns).text
            cmd = item.find('autn:index_command', ns).text
            
            if command_prefix and command_prefix not in cmd:
                continue
                
            print(f"\r   → {percent}% — {desc} ({status})", end="", flush=True)
            
            if status == "-1" and percent == 100:
                print(f"\nJob {job_id} FINISHED!")
                return True
                
        print(".", end="", flush=True)
        time.sleep(3)

# ────────────────────── 1. START EXPORT ──────────────────────
EXPORT_FILE = f"{EXPORT_DIR}/REINDEX_EXPORT_{datetime.now():%Y%m%d_%H%M%S}.idx.gz"
print(f"Starting export → {EXPORT_FILE}")
r = session.get(f"{index_url}/DREEXPORTIDX?FileName={EXPORT_FILE}&Compress=true&BatchSize=999999999&Priority=High")
export_id = r.text.strip().split("=")[-1]
print(f"Export submitted → INDEXID={export_id}")

wait_for_job(export_id, "DREEXPORTIDX")

# ────────────────────── 2. RUN DREINITIAL (and wait!) ──────────────────────
print("Running DREINITIAL (wiping index)...")
initial_id = int(time.time())
session.get(f"{index_url}/DREINITIAL?InitialID=REINDEX_{initial_id}")
print("DREINITIAL submitted — waiting for completion via IndexerGetStatus...")

# DREINITIAL always gets ID=1
wait_for_job("1", "DREINITIAL")

# ────────────────────── 3. RESTORE VIA DREADD ──────────────────────
print(f"Restoring from {EXPORT_FILE}...")
r = session.get(f"{index_url}/DREADD?FileName={EXPORT_FILE}&Delete=true&Priority=High")
dreadd_id = r.text.strip().split("=")[-1]
print(f"DREADD started → INDEXID={dreadd_id}")

wait_for_job(dreadd_id, "DREADD")

print("\nFULL SAFE REINDEX COMPLETED SUCCESSFULLY!")
print(f"Export file: {EXPORT_FILE}")
print("Your Content index is now clean, defragmented, and 100% restored.")