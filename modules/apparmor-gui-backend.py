import glob
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import threading

NIX_FILES = [
    "/etc/nixos/modules/apparmor.nix",
    "/home/John/Sync Obsidian/Nixos/Asus Configuration/modules/apparmor.nix",
]
APP_DIRS = [
    "/run/current-system/sw/share/applications",
    "/home/John/.local/share/applications",
    "/home/John/.local/share/flatpak/exports/share/applications",
    "/var/lib/flatpak/exports/share/applications",
]
BIN_DIRS = [
    "/run/current-system/sw/bin",
    "/run/current-system/sw/sbin",
    "/home/John/.local/bin",
    "/home/John/.nix-profile/bin",
]
CACHE = "/var/cache/apparmor/logprof"
POLICY_RE = re.compile(
    r'    "([^"]+)" = \{\n      state = "(complain|enforce|disable)";\n      profile = \'\'\n(.*?)\n      \'\';\n    \};',
    re.S,
)


def check(cmd):
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        raise SystemExit((result.stdout or f"{cmd[0]} failed").strip())
    return result.stdout


def run_text(cmd):
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return result.returncode, result.stdout


def include_roots():
    roots = []
    path = "/etc/apparmor/parser.conf"
    if not os.path.isfile(path):
        return roots
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("Include "):
            roots.append(line.split(None, 1)[1])
    return roots


def link_includes(directory):
    # One include directory does not contain every abstraction. Merge them so
    # aa-logprof and aa-cleanprof can resolve includes next to the profile.
    for name in ("tunables", "abstractions", "abi"):
        dest = os.path.join(directory, name)
        if os.path.islink(dest):
            os.unlink(dest)
        os.makedirs(dest, exist_ok=True)
        for root in include_roots():
            src = os.path.join(root, name)
            if not os.path.isdir(src):
                continue
            for entry in os.listdir(src):
                target = os.path.join(dest, entry)
                if os.path.lexists(target):
                    continue
                os.symlink(os.path.join(src, entry), target)


def write_file(path, text):
    st = os.stat(path)
    temporary = path + ".apparmor-gui.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chown(temporary, st.st_uid, st.st_gid)
    os.chmod(temporary, st.st_mode & 0o777)
    os.replace(temporary, path)


def unescape_body(body):
    lines = []
    for line in body.splitlines():
        lines.append(line[8:] if line.startswith("        ") else line)
    text = "\n".join(lines)
    return text.replace("''${", "${").replace("'''", "''")


def escape_body(body):
    body = body.replace("''", "'''").replace("${", "''${")
    lines = []
    for line in body.strip("\n").splitlines():
        lines.append(("        " + line) if line else "")
    return "\n".join(lines)


def parse_policies(text):
    return [
        {"key": match.group(1), "mode": match.group(2), "text": unescape_body(match.group(3))}
        for match in POLICY_RE.finditer(text)
    ]


def nix_text():
    for path in NIX_FILES:
        if os.path.isfile(path):
            return path, open(path, encoding="utf-8").read()
    return None, ""


def installed_text(key):
    path = os.path.join("/etc/apparmor.d", key)
    if not os.path.isfile(path):
        return None
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None


def saved_policies():
    _, text = nix_text()
    policies = parse_policies(text)
    for item in policies:
        item["source"] = item["text"]
        installed = installed_text(item["key"])
        item["runtime"] = installed if installed is not None else item["source"]
        item["name"] = profile_name(item["runtime"]) or profile_name(item["source"]) or item["key"]
        item["exec"] = attachment(item["runtime"]) or attachment(item["source"])
        item["audit"] = audit_on(item["runtime"]) or audit_on(item["source"])
        item["interpolated"] = "${" in item["source"]
    return policies


def file_id(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    return (st.st_dev, st.st_ino)


def profile_name(text):
    match = re.search(r"(?m)^[ \t]*profile\s+(\S+)", text)
    if match:
        return match.group(1).strip('"')
    match = re.search(r"(?m)^[ \t]*(/\S+)\s+(?:flags=\([^)]*\)\s*)?\{", text)
    if match:
        return match.group(1)
    return None


def attachment(text):
    match = re.search(r"(?m)^[ \t]*profile\s+\S+\s+(\S+)", text)
    if match and match.group(1).startswith("/"):
        return match.group(1)
    match = re.search(r"(?m)^[ \t]*(/\S+)\s+(?:flags=\([^)]*\)\s*)?\{", text)
    if match:
        return match.group(1)
    return None


def audit_on(text):
    match = re.search(r"flags=\(([^)]*)\)", text)
    if not match:
        return False
    return "audit" in [part.strip() for part in match.group(1).split(",")]


def set_audit_flag(text, enabled):
    def replace(match):
        flags = [part.strip() for part in match.group(1).split(",") if part.strip() and part.strip() != "audit"]
        if enabled:
            flags.append("audit")
        if not flags:
            return ""
        return " flags=(" + ",".join(flags) + ")"

    new, count = re.subn(r"[ \t]flags=\(([^)]*)\)", replace, text, count=1)
    if count == 0 and enabled:
        new, count = re.subn(r"\{", "flags=(audit) {", text, count=1)
    if count != 1:
        raise SystemExit("could not find the profile flags")
    return new


def policy_files():
    found = {}
    base = "/etc/apparmor.d"
    if not os.path.isdir(base):
        return found
    for name in os.listdir(base):
        path = os.path.join(base, name)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        profile = profile_name(text)
        if profile:
            found[profile] = name
    return found


def find_policy(name):
    for item in saved_policies():
        if item["name"] == name or item["key"] == name:
            return item
    return None


def profiles():
    data = json.loads(check(["aa-status", "--json"]))
    raw = data.get("profiles", {})
    saved = {item["name"]: item for item in saved_policies()}
    items = []
    if isinstance(raw, dict):
        pairs = list(raw.items()) if raw and all(isinstance(value, str) for value in raw.values()) else []
        if not pairs:
            for mode in ("enforce", "complain", "disable"):
                for name in raw.get(mode, []):
                    pairs.append((name, mode))
    else:
        pairs = []
    files = policy_files()
    seen = set()
    for name, mode in pairs:
        seen.add(name)
        item = saved.get(name, {})
        items.append({
            "name": name,
            "mode": mode,
            "policy": item.get("key") or files.get(name),
            "audit": bool(item.get("audit")),
            "exec": item.get("exec") or "",
            "saved": bool(item),
        })
    for item in saved.values():
        if item["name"] in seen or item["mode"] == "disable":
            continue
        items.append({
            "name": item["name"],
            "mode": item["mode"],
            "policy": item["key"],
            "audit": item["audit"],
            "exec": item.get("exec") or "",
            "saved": True,
        })
    items.sort(key=lambda item: item["name"])
    return items, data.get("processes", {})


def log_lines():
    try:
        out = check(["journalctl", "-b", "-g", "apparmor=", "--no-pager", "-n", "80", "-o", "cat"])
    except SystemExit:
        return []
    decoded = subprocess.run(["aa-decode"], input=out, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    text = decoded.stdout if decoded.returncode == 0 and decoded.stdout.strip() else out
    return [line for line in text.splitlines() if "apparmor=" in line]


def enabled():
    return subprocess.run(["aa-enabled", "-q"]).returncode == 0


def unconfined():
    code, out = run_text(["aa-unconfined", "--paranoid", "--short"])
    lines = [line for line in out.splitlines() if line.strip()] if code == 0 or out.strip() else []
    return lines[:80], len(lines)


def parse_units(text, scope):
    items = []
    current = {}
    for line in text.splitlines() + [""]:
        if not line.strip():
            if current.get("Id") and current.get("exec"):
                items.append({
                    "id": current["Id"],
                    "scope": scope,
                    "exec": current["exec"],
                    "pid": current.get("MainPID", "0"),
                })
            current = {}
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "ExecStart":
            match = re.search(r"path=([^ ;]+)", value)
            current["exec"] = match.group(1) if match else ""
        else:
            current[key] = value
    return items


def services():
    items = []
    commands = [
        ("system", ["systemctl", "show", "--type=service", "--state=running", "-p", "Id", "-p", "ExecStart", "-p", "MainPID"]),
        ("user", ["systemctl", "--user", "-M", "John@", "show", "--type=service", "--state=running", "-p", "Id", "-p", "ExecStart", "-p", "MainPID"]),
    ]
    for scope, cmd in commands:
        code, out = run_text(cmd)
        if code == 0:
            items.extend(parse_units(out, scope))
    items.sort(key=lambda item: (item["scope"], item["id"]))
    return items


def apps():
    items = []
    seen = set()
    for directory in APP_DIRS:
        for path in sorted(glob.glob(os.path.join(directory, "*.desktop"))):
            entry = parse_desktop(path)
            if not entry or entry["exec"] in seen:
                continue
            seen.add(entry["exec"])
            items.append(entry)
    items.sort(key=lambda item: item["name"].lower())
    return items


def parse_desktop(path):
    name = None
    exe = None
    hidden = False
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return None
    for line in lines:
        if line.startswith("Name=") and name is None:
            name = line.split("=", 1)[1].strip()
        elif line.startswith("Exec=") and exe is None:
            exe = line.split("=", 1)[1].strip()
        elif line.startswith("NoDisplay=true") or line.startswith("Hidden=true"):
            hidden = True
    if hidden or not name or not exe:
        return None
    try:
        tokens = [token for token in shlex.split(exe) if not token.startswith("%")]
    except ValueError:
        tokens = exe.split()
    while tokens and (tokens[0] == "env" or "=" in tokens[0]):
        tokens.pop(0)
    if not tokens:
        return None
    if tokens[0] == "flatpak" or tokens[0].endswith("/flatpak"):
        app_id = next((token for token in reversed(tokens[1:]) if not token.startswith("-") and "." in token), name)
        return {"name": name, "exec": app_id, "kind": "flatpak"}
    token = tokens[0]
    if not token.startswith("/"):
        token = which(token)
        if not token:
            return None
    if not os.path.isfile(token):
        return None
    return {"name": name, "exec": token, "kind": "app"}


def which(name):
    for directory in BIN_DIRS:
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def index_processes(processes):
    by_pid = {}
    by_exe = {}
    if not isinstance(processes, dict):
        return by_pid, by_exe
    for exe, entries in processes.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if entry.get("status") == "unconfined" and str(entry.get("pid")) in by_pid:
                continue
            by_pid[str(entry.get("pid"))] = entry
            by_exe[exe] = entry
            if os.path.exists(exe):
                by_exe[os.path.realpath(exe)] = entry
    return by_pid, by_exe


def match_profile(exec_path, pid, by_pid, by_exe, attached, attached_id):
    hit = by_pid.get(str(pid)) if pid and pid != "0" else None
    if not hit:
        hit = by_exe.get(exec_path)
        if not hit and exec_path and os.path.exists(exec_path):
            hit = by_exe.get(os.path.realpath(exec_path))
    if hit and hit.get("status") != "unconfined":
        return hit.get("profile"), hit.get("status")
    real = os.path.realpath(exec_path) if exec_path and os.path.exists(exec_path) else exec_path
    saved = attached.get(exec_path) or attached.get(real)
    if not saved and exec_path:
        saved = attached_id.get(file_id(exec_path))
    if saved:
        return saved["name"], saved["mode"]
    return None, None


def overview():
    loaded, processes = profiles()
    by_pid, by_exe = index_processes(processes)
    attached = {}
    attached_id = {}
    for item in saved_policies():
        if not item.get("exec"):
            continue
        attached[item["exec"]] = item
        if os.path.exists(item["exec"]):
            attached[os.path.realpath(item["exec"])] = item
            ident = file_id(item["exec"])
            if ident:
                attached_id[ident] = item
    service_rows = []
    for item in services():
        profile, mode = match_profile(item["exec"], item["pid"], by_pid, by_exe, attached, attached_id)
        item["profile"] = profile
        item["mode"] = mode
        service_rows.append(item)
    app_rows = []
    for item in apps():
        if item["kind"] == "flatpak":
            item["profile"] = None
            item["mode"] = None
        else:
            profile, mode = match_profile(item["exec"], None, by_pid, by_exe, attached, attached_id)
            item["profile"] = profile
            item["mode"] = mode
        app_rows.append(item)
    lines, count = unconfined()
    return {
        "enabled": enabled(),
        "profiles": loaded,
        "services": service_rows,
        "apps": app_rows,
        "unconfined": lines,
        "unconfined_count": count,
        "log": log_lines(),
    }


def load_text(text, mode):
    handle = tempfile.NamedTemporaryFile("w", delete=False)
    handle.write(text)
    if not text.endswith("\n"):
        handle.write("\n")
    handle.close()
    try:
        if mode == "disable":
            check(["apparmor_parser", "-R", handle.name])
        elif mode == "complain":
            check(["apparmor_parser", "-r", "-C", handle.name])
        else:
            check(["apparmor_parser", "-r", handle.name])
    finally:
        os.unlink(handle.name)


def update_state(text, key, mode):
    pattern = rf'("{re.escape(key)}" = \{{.*?state = ")(?:complain|enforce|disable)(")'
    new, count = re.subn(pattern, rf"\g<1>{mode}\2", text, count=1, flags=re.S)
    if count != 1:
        return None
    return new


def update_nix(mutator):
    saved = []
    for path in NIX_FILES:
        if not os.path.isfile(path):
            continue
        text = open(path, encoding="utf-8").read()
        new = mutator(text)
        if new is None:
            continue
        if new != text:
            write_file(path, new)
        saved.append(path)
    if not saved:
        raise SystemExit("apparmor.nix could not be updated")
    return saved


def replace_policy(text, key, mode, body):
    replacement = (
        f'    "{key}" = {{\n'
        f'      state = "{mode}";\n'
        f"      profile = ''\n"
        f"{escape_body(body)}\n"
        f"      '';\n"
        f"    }};"
    )
    match = None
    for found in POLICY_RE.finditer(text):
        if found.group(1) == key:
            match = found
            break
    if match:
        return text[:match.start()] + replacement + text[match.end():]
    needle = "security.apparmor.policies = {"
    if needle not in text:
        return None
    return text.replace(needle, needle + "\n" + replacement, 1)


def set_mode(name, mode):
    if mode not in ("enforce", "complain", "disable"):
        raise SystemExit("mode must be enforce, complain, or disable")
    item = find_policy(name)
    if not item:
        if mode != "disable":
            raise SystemExit(f"{name} is not saved in apparmor.nix. Disable unloads a profile that was loaded by hand.")
        load_text(unload_stub(name), "disable")
        return {"name": name, "mode": mode, "saved": []}
    load_text(item["runtime"], mode)
    saved = update_nix(lambda text: update_state(text, item["key"], mode))
    return {"name": item["name"], "mode": mode, "policy": item["key"], "saved": saved}


def unload_stub(name):
    if name.startswith("/"):
        return f"{name} flags=(complain) {{\n  /dev/null r,\n}}\n"
    return f"profile {name} {name} flags=(complain) {{\n  /dev/null r,\n}}\n"


def set_audit(name, state):
    if state not in ("on", "off"):
        raise SystemExit("audit must be on or off")
    item = find_policy(name)
    if not item:
        raise SystemExit(f"{name} is not saved in apparmor.nix")
    enabled = state == "on"
    if item["mode"] != "disable":
        load_text(set_audit_flag(item["runtime"], enabled), item["mode"])

    def mutate(text):
        match = None
        for found in POLICY_RE.finditer(text):
            if found.group(1) == item["key"]:
                match = found
                break
        if not match:
            return None
        return text[:match.start(3)] + set_audit_flag(match.group(3), enabled) + text[match.end(3):]

    saved = update_nix(mutate)
    return {"name": item["name"], "audit": enabled, "saved": saved}


def stable_path(program):
    program = os.path.abspath(program)
    if not os.path.isfile(program):
        raise SystemExit("choose a program path that exists")
    if program.startswith("/run/current-system/sw/"):
        return program, False
    real = os.path.realpath(program)
    for base in ("bin", "sbin", "libexec"):
        root = os.path.join("/run/current-system/sw", base)
        if not os.path.isdir(root):
            continue
        for dirpath, _, names in os.walk(root):
            for name in names:
                candidate = os.path.join(dirpath, name)
                if os.path.islink(candidate) and os.path.realpath(candidate) == real:
                    return candidate, False
    return program, program.startswith("/nix/store/")


def policy_key(path):
    parts = [part for part in path.split("/") if part]
    if parts[:3] == ["run", "current-system", "sw"]:
        parts = parts[3:]
    elif len(parts) >= 3 and parts[:2] == ["nix", "store"]:
        parts = parts[3:]
    elif len(parts) >= 3 and parts[:2] == ["run", "wrappers"]:
        parts = parts[3:]
    key = ".".join(parts)
    key = re.sub(r"[^A-Za-z0-9._+-]", ".", key).strip(".")
    return (key or "profile")[:120]


def existing_for_path(path):
    real = os.path.realpath(path) if os.path.exists(path) else path
    ident = file_id(path)
    for item in saved_policies():
        attach = item.get("exec")
        if not attach:
            continue
        attach_real = os.path.realpath(attach) if os.path.exists(attach) else attach
        if path in (attach, attach_real) or real in (attach, attach_real):
            return item
        if ident and ident == file_id(attach):
            return item
    return None


def create(program):
    if program.endswith("/flatpak") or os.path.basename(program) == "flatpak":
        raise SystemExit("Flatpak apps use the Flatpak sandbox. AppArmor would only wrap the flatpak command, not the app.")
    attach, in_store = stable_path(program)
    found = existing_for_path(attach)
    if found:
        result = set_mode(found["name"], "complain")
        result["existed"] = True
        result["store"] = in_store
        return result
    name = os.path.basename(attach)
    if any(item["name"] == name for item in saved_policies()):
        name = policy_key(attach).replace(".", "-")
    key = policy_key(attach)
    body = (
        "include <tunables/global>\n"
        f"profile {name} {attach} flags=(attach_disconnected) {{\n"
        "  include <abstractions/base>\n"
        "  include <abstractions/nameservice>\n"
        f"  {attach} mr,\n"
        "}\n"
    )
    load_text(body, "complain")
    saved = update_nix(lambda text: replace_policy(text, key, "complain", body))
    return {"name": name, "mode": "complain", "policy": key, "exec": attach, "saved": saved, "store": in_store, "existed": False}


def show(name):
    item = find_policy(name)
    if not item:
        raise SystemExit(f"{name} is not saved in apparmor.nix")
    return {"name": item["name"], "policy": item["key"], "mode": item["mode"], "text": item["runtime"]}


def refuse_interpolated(item):
    if item.get("interpolated"):
        raise SystemExit(
            f"{item['name']} is tied to a Nix package path in apparmor.nix. "
            "Complain, enforce, disable, and audit still work. Edit its rules in that file."
        )


def clean(name):
    item = find_policy(name)
    if not item:
        raise SystemExit(f"{name} is not saved in apparmor.nix")
    refuse_interpolated(item)
    directory = tempfile.mkdtemp(prefix="apparmor-clean-")
    try:
        link_includes(directory)
        path = os.path.join(directory, item["key"])
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(item["runtime"])
        program = item.get("exec") or item["name"]
        code, out = run_text(["aa-cleanprof", "-s", "-d", directory, program])
        if code != 0:
            raise SystemExit(out.strip() or "aa-cleanprof failed")
        body = open(path, encoding="utf-8").read()
    finally:
        for entry in os.listdir(directory):
            candidate = os.path.join(directory, entry)
            if os.path.islink(candidate) or os.path.isfile(candidate):
                os.unlink(candidate)
        os.rmdir(directory)
    if item["mode"] != "disable":
        load_text(body, item["mode"])
    saved = update_nix(lambda text: replace_policy(text, item["key"], item["mode"], body))
    return {"name": item["name"], "saved": saved, "output": out.strip()}


def forget(name):
    item = find_policy(name)
    if not item:
        raise SystemExit(f"{name} is not saved in apparmor.nix")
    try:
        load_text(item["runtime"], "disable")
    except SystemExit:
        pass
    def remove(text):
        match = None
        for found in POLICY_RE.finditer(text):
            if found.group(1) == item["key"]:
                match = found
                break
        if not match:
            return None
        end = match.end()
        if text[end:end + 1] == "\n":
            end += 1
        return text[:match.start()] + text[end:]
    saved = update_nix(remove)
    return {"name": item["name"], "removed": item["key"], "saved": saved}


def import_file(path):
    if not os.path.isfile(path):
        raise SystemExit("that profile file does not exist")
    body = open(path, encoding="utf-8", errors="replace").read()
    name = profile_name(body)
    if not name or "{" not in body:
        raise SystemExit("that file does not contain an AppArmor profile")
    attach = attachment(body)
    key = policy_key(attach or name)
    load_text(body, "complain")
    saved = update_nix(lambda text: replace_policy(text, key, "complain", body))
    return {"name": name, "policy": key, "mode": "complain", "saved": saved}


def reload_all():
    loaded = []
    for item in saved_policies():
        if item["mode"] == "disable":
            continue
        load_text(item["runtime"], item["mode"])
        loaded.append(item["name"])
    return loaded


def remove_unknown():
    code, out = run_text(["aa-remove-unknown"])
    if code != 0:
        raise SystemExit(out.strip() or "aa-remove-unknown failed")
    return {"ok": True, "output": out.strip(), "restored": reload_all()}


def teardown():
    code, out = run_text(["aa-teardown"])
    if code != 0:
        raise SystemExit(out.strip() or "aa-teardown failed")
    return {"ok": True, "output": out.strip()}


def status_text():
    return {"text": check(["aa-status"])}


def features_text():
    return {"text": check(["aa-features-abi", "-x", "--stdout"])}


def seed_cache():
    os.makedirs(CACHE, exist_ok=True)
    link_includes(CACHE)
    for name in os.listdir(CACHE):
        path = os.path.join(CACHE, name)
        if os.path.isfile(path) and not os.path.islink(path):
            os.unlink(path)
    for item in saved_policies():
        if item["mode"] == "disable":
            continue
        with open(os.path.join(CACHE, item["key"]), "w", encoding="utf-8") as handle:
            handle.write(item["runtime"])
    return file_hashes(CACHE)


def file_hashes(directory):
    found = {}
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if os.path.isfile(path) and not os.path.islink(path):
            found[name] = hashlib.sha256(open(path, "rb").read()).hexdigest()
    return found


def import_learned(before):
    saved = []
    skipped = []
    current = {item["key"]: item for item in saved_policies()}
    for name, digest in file_hashes(CACHE).items():
        if before.get(name) == digest:
            continue
        body = open(os.path.join(CACHE, name), encoding="utf-8", errors="replace").read()
        if "{" not in body:
            continue
        previous = current.get(name)
        if previous and previous.get("interpolated"):
            skipped.append(previous["name"])
            continue
        mode = previous["mode"] if previous else "complain"
        if mode != "disable":
            load_text(body, mode)
        update_nix(lambda text, key=name, mode=mode, body=body: replace_policy(text, key, mode, body))
        saved.append(profile_name(body) or name)
    return saved, skipped


def normalize_log(text):
    # libapparmor reads "type=AVC msg=audit(time:serial): apparmor=...".
    # The kernel journal writes "audit: type=1400 audit(time:serial): apparmor=...".
    lines = []
    seen = set()
    for line in text.splitlines():
        match = re.search(r"audit\((\d+\.\d+:\d+)\):\s*(apparmor=.*)$", line)
        if not match:
            continue
        event = f"type=AVC msg=audit({match.group(1)}): {match.group(2)}"
        if event not in seen:
            seen.add(event)
            lines.append(event)
    return "\n".join(lines) + ("\n" if lines else "")


def logprof():
    before = seed_cache()
    log = subprocess.run(
        ["journalctl", "-b", "-k", "-g", "apparmor=", "--no-pager", "-o", "cat"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    handle = tempfile.NamedTemporaryFile("w", delete=False)
    handle.write(normalize_log(log.stdout or ""))
    handle.close()
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    child = subprocess.Popen(
        ["aa-logprof", "-d", CACHE, "-f", handle.name, "-j"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=env,
    )

    def pump_in():
        try:
            for line in sys.stdin:
                if child.poll() is not None:
                    break
                child.stdin.write(line)
                child.stdin.flush()
        except (BrokenPipeError, OSError):
            pass
        try:
            child.stdin.close()
        except OSError:
            pass

    threading.Thread(target=pump_in, daemon=True).start()
    error = ""
    try:
        for line in child.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                print(json.dumps({"dialog": "info", "data": line}), flush=True)
                continue
            if message.get("dialog") == "changes" and message.get("filename"):
                try:
                    message["text"] = open(message["filename"], encoding="utf-8", errors="replace").read()[:20000]
                except OSError as exc:
                    message["text"] = str(exc)
            print(json.dumps(message), flush=True)
        error = child.stderr.read()[-4000:]
        code = child.wait()
    finally:
        os.unlink(handle.name)
    saved, skipped = import_learned(before) if code == 0 else ([], [])
    print(json.dumps({
        "dialog": "done",
        "code": code,
        "saved": saved,
        "skipped": skipped,
        "error": error.strip(),
    }), flush=True)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("missing command")
    command = sys.argv[1]
    if command == "overview":
        print(json.dumps(overview()))
    elif command == "log":
        print(json.dumps(log_lines()))
    elif command == "set" and len(sys.argv) == 4:
        print(json.dumps(set_mode(sys.argv[2], sys.argv[3])))
    elif command == "audit" and len(sys.argv) == 4:
        print(json.dumps(set_audit(sys.argv[2], sys.argv[3])))
    elif command == "create" and len(sys.argv) == 3:
        print(json.dumps(create(sys.argv[2])))
    elif command == "show" and len(sys.argv) == 3:
        print(json.dumps(show(sys.argv[2])))
    elif command == "clean" and len(sys.argv) == 3:
        print(json.dumps(clean(sys.argv[2])))
    elif command == "forget" and len(sys.argv) == 3:
        print(json.dumps(forget(sys.argv[2])))
    elif command == "import-file" and len(sys.argv) == 3:
        print(json.dumps(import_file(sys.argv[2])))
    elif command == "reload":
        print(json.dumps({"loaded": reload_all()}))
    elif command == "remove-unknown":
        print(json.dumps(remove_unknown()))
    elif command == "teardown":
        print(json.dumps(teardown()))
    elif command == "status":
        print(json.dumps(status_text()))
    elif command == "features":
        print(json.dumps(features_text()))
    elif command == "logprof":
        logprof()
    else:
        raise SystemExit("unknown command")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.stderr or exc.stdout or f"command failed: {exc.returncode}")
