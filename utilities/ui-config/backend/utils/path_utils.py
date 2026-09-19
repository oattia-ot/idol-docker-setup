"""
backend/utils/path_utils.py
Resolves IDOL_BASE_PATH (the project root used to locate config files,
flow exports, etc.) in a way that works in Docker, on a local dev
machine, or from any mount point.

This consolidates two near-identical blocks that existed back-to-back
in the original app.py: the first block computed a base path and then
was immediately and unconditionally overwritten by a second, slightly
more thorough block. The first block was dead code; only the logic
below (equivalent to the second block) ever took effect.
"""

import os


PROJECT_ROOT_MARKERS = ("idol-docker-setup", "idol", "setup")
PROJECT_ROOT_FILES = ("docker-compose.yml",)
PROJECT_ROOT_DIRS = ("idol-containers-toolkit",)


def _looks_like_project_root(path: str) -> bool:
    if os.path.basename(path) in PROJECT_ROOT_MARKERS:
        return True
    if any(os.path.exists(os.path.join(path, f)) for f in PROJECT_ROOT_FILES):
        return True
    if any(os.path.exists(os.path.join(path, d)) for d in PROJECT_ROOT_DIRS):
        return True
    return False


def _search_upwards_for_project_root(start_dir: str, max_levels: int = 10) -> str:
    base_dir = start_dir
    for _ in range(max_levels):
        parent = os.path.dirname(base_dir)
        if parent == base_dir:  # reached filesystem root
            break
        if _looks_like_project_root(parent):
            return parent
        base_dir = parent
    return base_dir


def resolve_idol_base_path(script_file: str, env: dict = None) -> str:
    """
    Resolve IDOL_BASE_PATH with the following priority:
    1. IDOL_BASE_PATH environment variable (highest priority)
    2. Search upwards for a directory named 'idol-docker-setup'
    3. Fallback to ./idol-docker-setup relative to current working directory
    """
    env = env if env is not None else os.environ

    # 1. Environment variable takes highest priority
    base_path = env.get("IDOL_BASE_PATH")
    if base_path:
        return base_path.rstrip("/")

    script_dir = os.path.dirname(os.path.abspath(script_file))

    # 2. Walk upwards looking specifically for a folder named 'idol-docker-setup'
    current = script_dir
    for _ in range(15):
        if os.path.basename(current) == 'idol-docker-setup':
            return current.rstrip('/')
        parent = os.path.dirname(current)
        if parent == current:  # reached filesystem root
            break
        current = parent

    # 3. Final fallback: ./idol-docker-setup relative to CWD
    fallback = os.path.join(os.getcwd(), 'idol-docker-setup')
    return fallback.rstrip('/')
