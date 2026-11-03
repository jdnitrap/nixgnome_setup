#apparmor-gui.nix

{ config, pkgs, lib, ... }:

let
  dashboard = pkgs.writeScriptBin "apparmor-dashboard" ''
    #!${pkgs.python3}/bin/python3
    import json, subprocess
    from http.server import BaseHTTPRequestHandler, HTTPServer

    PORT = 8088

    def run(cmd):
        try:
            return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        except Exception:
            return ""

    def profiles():
        out = run(["aa-status", "--json"])
        if out:
            try:
                data = json.loads(out)
                items = []
                for mode in ("enforce", "complain"):
                    for name in data.get("profiles", {}).get(mode, []):
                        items.append({"name": name, "mode": mode})
                return items
            except Exception:
                pass
        items = []
        for line in run(["aa-status"]).splitlines():
            line = line.strip()
            if line.startswith("enforce "):
                items.append({"name": line.split(" ", 1)[1], "mode": "enforce"})
            elif line.startswith("complain "):
                items.append({"name": line.split(" ", 1)[1], "mode": "complain"})
        return items

    def denials():
        out = run(["journalctl", "-b", "-g", "apparmor", "--no-pager", "-n", "40", "-o", "short"])
        return [l for l in out.splitlines() if "apparmor" in l.lower()]

    PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>AppArmor</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; }
  body { margin: 0; font: 15px/1.5 system-ui, sans-serif; background: #101412; color: #e7eee9; }
  header { padding: 20px 24px; border-bottom: 1px solid #243028; }
  h1 { margin: 0; font-size: 20px; }
  main { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 16px; }
  section { background: #171c19; border: 1px solid #243028; border-radius: 10px; padding: 14px; }
  h2 { margin: 0 0 10px; font-size: 14px; color: #8eae7a; }
  .row { display: flex; justify-content: space-between; align-items: center; padding: 8px 0; border-bottom: 1px solid #243028; }
  .row:last-child { border-bottom: 0; }
  .mode { font-size: 12px; padding: 2px 8px; border-radius: 999px; }
  .enforce { background: #1e3a2f; color: #3dcc9a; }
  .complain { background: #3a2e1e; color: #e4a15a; }
  button { background: #243028; color: #e7eee9; border: 0; border-radius: 6px; padding: 4px 10px; cursor: pointer; }
  button:hover { background: #2d3a32; }
  pre { white-space: pre-wrap; font-size: 12px; color: #c9d4cd; }
  @media (max-width: 800px) { main { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<header><h1>AppArmor</h1></header>
<main>
  <section>
    <h2>Profiles</h2>
    <div id="profiles">Loading...</div>
  </section>
  <section>
    <h2>Recent denials</h2>
    <pre id="denials">Loading...</pre>
  </section>
</main>
<script>
async function load() {
  const p = await (await fetch("/api/status")).json();
  const d = await (await fetch("/api/denials")).json();
  const rows = p.map(function(x) {
    var next = x.mode === "enforce" ? "complain" : "enforce";
    var label = x.mode === "enforce" ? "to complain" : "to enforce";
    return "<div class=\"row\"><span>" + x.name + "</span><span><span class=\"mode " + x.mode + "\">" + x.mode + "</span> <button onclick=\"switchMode('" + x.name + "','" + next + "')\">" + label + "</button></span></div>";
  }).join("");
  document.getElementById("profiles").innerHTML = rows || "No profiles loaded.";
  document.getElementById("denials").textContent = d.join("\n") || "No denials this boot.";
}
async function switchMode(name, mode) {
  await fetch("/api/switch", { method: "POST", headers: {"Content-Type":"application/json"}, body: JSON.stringify({name: name, mode: mode}) });
  load();
}
load();
setInterval(load, 8000);
</script>
</body>
</html>"""

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass
        def _send(self, code, body, ctype="text/html"):
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def do_GET(self):
            if self.path == "/api/status":
                self._send(200, json.dumps(profiles()), "application/json")
            elif self.path == "/api/denials":
                self._send(200, json.dumps(denials()), "application/json")
            else:
                self._send(200, PAGE)
        def do_POST(self):
            if self.path == "/api/switch":
                n = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(n) or b"{}")
                name = body.get("name", "")
                mode = body.get("mode", "")
                if name and mode in ("enforce", "complain"):
                    run(["pkexec", "apparmor-switch", name, mode])
                self._send(200, "{}", "application/json")

    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
  '';

  switch = pkgs.writeScriptBin "apparmor-switch" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    name="$1"
    mode="$2"
    file="/etc/apparmor.d/$name"
    [ -f "$file" ] || exit 1
    if [ "$mode" = "enforce" ]; then
      ${pkgs.apparmor-parser}/bin/apparmor_parser -r "$file"
    else
      ${pkgs.apparmor-parser}/bin/apparmor_parser -r -C "$file"
    fi
  '';
in
{
  environment.systemPackages = [ dashboard switch pkgs.apparmor-utils ];

  environment.etc."xdg/applications/apparmor-dashboard.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=AppArmor
    Comment=View and switch AppArmor profiles
    Exec=${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:8088
    Icon=security-high
    Terminal=false
    Categories=System;Security;
    StartupNotify=true
  '';

  systemd.user.services.apparmor-dashboard = {
    description = "AppArmor local dashboard";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${dashboard}/bin/apparmor-dashboard";
      Restart = "on-failure";
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.policykit.exec" &&
          action.lookup("command") &&
          action.lookup("command").indexOf("apparmor-switch") !== -1 &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
}
