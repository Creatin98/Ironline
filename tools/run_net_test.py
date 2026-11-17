"""Starts a host and a client Godot process and checks the network game over localhost.

Usage:  py -3 tools/run_net_test.py [pfad/zu/godot] [port]
The Godot binary can also come from the GODOT environment variable or the PATH.
Exit code 0 = both processes passed.
"""
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def find_godot():
    if len(sys.argv) > 1 and sys.argv[1]:
        return sys.argv[1]
    for candidate in (os.environ.get("GODOT"), shutil.which("godot"), shutil.which("godot4")):
        if candidate:
            return candidate
    sys.exit("Godot nicht gefunden: Pfad als Argument übergeben oder GODOT setzen.")


def start(godot, role, port, scenario):
    cmd = [godot, "--headless", "--path", ROOT, "tests/net_test.tscn", "--", f"--role={role}", f"--port={port}", f"--scenario={scenario}"]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")


def run_scenario(godot, port, scenario):
    host = start(godot, "host", port, scenario)
    time.sleep(2.0)
    client = start(godot, "client", port, scenario)
    results = {}
    for name, proc in (("host", host), ("client", client)):
        try:
            out, _ = proc.communicate(timeout=240)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
            out += "\n[runner] Zeitüberschreitung, Prozess beendet"
        results[name] = (proc.returncode, out)
    ok = True
    for name, (code, out) in results.items():
        print(f"===== {scenario}: {name} (Exit {code}) =====")
        for line in out.splitlines():
            if line.startswith(("[", "NETTEST", "ERROR", "SCRIPT ERROR", "WARNING: ")) or "rror" in line:
                print(line)
        ok = ok and code == 0
    return ok


def main():
    godot = find_godot()
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 7791
    ok = run_scenario(godot, str(port), "full")
    ok = run_scenario(godot, str(port + 1), "leave") and ok
    print("Ergebnis:", "OK" if ok else "FEHLGESCHLAGEN")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
