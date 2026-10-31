#!/usr/bin/env python3
"""Ship nixos-config `main` to a host through ronove's fleet-deployer API.

    ship.py <host> [--mode test|switch|boot] [--rev SHA] [--force]
    ship.py --status

Exits 0 only if the deploy succeeded and the host runs what `main` builds.
Standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = "http://ronove.home.mingalev.net:8090"
TOKEN_FILE = "/mnt/pegasus/secrets/fleet-deployer/api-token"
EVAL_TIMEOUT = 20 * 60
JOB_TIMEOUT = 60 * 60
SETTLE_TIMEOUT = 3 * 60


class Api:
    def __init__(self, url: str):
        self.url = url.rstrip("/")
        self.token: str | None = None

    def call(self, method: str, path: str, body: dict | None = None, timeout: float = 15):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url + path, data=data, method=method)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.load(resp)

    def get(self, path: str):
        return self.call("GET", path)

    def get_patiently(self, path: str, deadline: float):
        """GET that rides out the deployer restarting itself (ronove deploys)."""
        while True:
            try:
                return self.get(path)
            except (urllib.error.URLError, ConnectionError, TimeoutError):
                if time.time() > deadline:
                    raise
                time.sleep(3)

    def post(self, path: str, body: dict | None = None):
        return self.call("POST", path, body if body is not None else {})


def die(msg: str, code: int = 1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def authorize(api: Api) -> None:
    if api.get("/api/session")["can_act"]:
        return
    token = os.environ.get("FLEET_TOKEN")
    if not token and os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            token = f.read().strip()
    if not token:
        die(f"not on a trusted network and no token (set FLEET_TOKEN or provide {TOKEN_FILE})")
    api.token = token
    if not api.get("/api/session")["can_act"]:
        die("the API token was rejected")


def local_main_sha() -> str | None:
    """The `main` bookmark of the jj repo we're in (what was just pushed)."""
    try:
        out = subprocess.run(
            ["jj", "log", "-r", "main", "--no-graph", "-T", "commit_id"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    sha = out.stdout.strip()
    return sha if out.returncode == 0 and len(sha) == 40 else None


def short(sha: str | None) -> str:
    return sha[:8] if sha else "-"


def store(path: str | None) -> str:
    return path.rsplit("/", 1)[-1][:8] if path else "-"


def describe(h: dict) -> str:
    flags = f" [{', '.join(h['flags'])}]" if h["flags"] else ""
    line = (
        f"{h['name']:14} {h['state']:13}{flags}  runs {store(h['current_path'])}"
        f" (commit {short(h['current_commit'])})  main builds {store(h['expected_path'])}"
        f"  checked {h['last_success_at'] or 'never'}"
    )
    if h.get("error"):
        line += f"\n{'':16}error: {h['error']}"
    if h.get("expected_error"):
        line += f"\n{'':16}evaluation failed: {h['expected_error'].splitlines()[-1]}"
    return line


def status(api: Api) -> int:
    m = api.get("/api/main")
    print(f"main {short(m['sha'])} {m['subject'] or ''} (fetched {m['fetched_at']})")
    for h in api.get("/api/hosts"):
        print("  " + describe(h))
    return 0


def wait_for_evaluation(api: Api, host: str, want_sha: str | None) -> dict:
    deadline = time.time() + EVAL_TIMEOUT
    announced = False
    while True:
        h = api.get(f"/api/hosts/{host}")
        sha = h["main_sha"]
        evaluated = h["expected_path"] or h["expected_error"]
        if sha and evaluated and (want_sha is None or sha == want_sha):
            return h
        if time.time() > deadline:
            die(f"timed out waiting for the deployer to evaluate {short(want_sha) if want_sha else 'main'} for {host}")
        if not announced:
            target = short(want_sha) if want_sha else "main"
            print(f"waiting for the deployer to fetch and evaluate {target} for {host} (can take minutes)...")
            announced = True
        time.sleep(10)


def follow_job(api: Api, job_id: int) -> dict:
    deadline = time.time() + JOB_TIMEOUT
    offset = 0
    while True:
        log = api.get_patiently(f"/api/jobs/{job_id}/log?offset={offset}", deadline)
        if log["text"]:
            sys.stdout.write(log["text"])
            sys.stdout.flush()
        offset = log["offset"]
        if log["state"] in ("succeeded", "failed"):
            return api.get_patiently(f"/api/jobs/{job_id}", deadline)
        if time.time() > deadline:
            die(f"job #{job_id} still {log['state']} after {JOB_TIMEOUT // 60} min")
        time.sleep(3)


def settle(api: Api, host: str, job: dict) -> dict:
    """Wait until the host reports the system the job deployed."""
    deadline = time.time() + SETTLE_TIMEOUT
    while True:
        h = api.get_patiently(f"/api/hosts/{host}", deadline)
        landed = h["boot_path"] if job["mode"] == "boot" else h["current_path"]
        if landed == job["expected_path"] or time.time() > deadline:
            return h
        time.sleep(5)


def ship(api: Api, host: str, mode: str, rev: str | None, force: bool) -> int:
    authorize(api)
    api.post("/api/refresh")
    want = rev or local_main_sha()
    h = wait_for_evaluation(api, host, want)
    print("before: " + describe(h))
    if not h["deploy"]:
        die(f"{host} is status-only (self-served); nothing to ship from here")
    if h["expected_error"]:
        die(f"main does not evaluate for {host}")
    if h["state"] == "in_sync" and mode != "boot" and not force and "boot_differs" not in h["flags"]:
        print(f"{host} already runs what main builds; nothing to do (use --force to redeploy)")
        return 0
    if h["active_job"]:
        die(f"{host} already has deploy #{h['active_job']} in progress")

    job_id = api.post("/api/deploy", {"host": host, "mode": mode, "rev": h["main_sha"]})["job"]
    print(f"queued deploy #{job_id}: nixos-rebuild {mode} -> {host} at {short(h['main_sha'])}\n")
    job = follow_job(api, job_id)
    print(f"\ndeploy #{job_id}: {job['state']}" + (f" ({job['error']})" if job["error"] else ""))
    after = settle(api, host, job)
    print("after:  " + describe(after))

    landed = after["boot_path"] if mode == "boot" else after["current_path"]
    ok = job["state"] == "succeeded" and landed == job["expected_path"]
    if not ok:
        print(f"{host} does not run the expected system {store(job['expected_path'])}", file=sys.stderr)
    return 0 if ok else 1


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("host", nargs="?")
    p.add_argument("--mode", choices=("test", "switch", "boot"), default="switch")
    p.add_argument("--rev", help="commit to wait for and ship (default: local jj `main`)")
    p.add_argument("--force", action="store_true", help="deploy even if the host is already in sync")
    p.add_argument("--status", action="store_true", help="show all hosts and exit")
    p.add_argument("--url", default=os.environ.get("FLEET_DEPLOYER_URL", DEFAULT_URL))
    args = p.parse_args()

    api = Api(args.url)
    try:
        if args.status or not args.host:
            return status(api)
        return ship(api, args.host, args.mode, args.rev, args.force)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        die(f"{e.code} from {e.url}: {detail}")
    except urllib.error.URLError as e:
        die(f"cannot reach {args.url}: {e.reason}")


if __name__ == "__main__":
    sys.exit(main())
