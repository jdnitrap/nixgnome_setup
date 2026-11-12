#apparmor-gui.nix
# A GNOME window for the AppArmor tools. Mode changes are applied now and
# written into apparmor.nix so the next rebuild keeps them.

{ pkgs, lib, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

  backend = pkgs.writeShellScriptBin "apparmor-gui-backend" ''
    export PATH=${lib.makeBinPath [
      pkgs.apparmor-bin-utils
      pkgs.apparmor-utils
      pkgs.apparmor-parser
      pkgs.systemd
      pkgs.diffutils
      pkgs.coreutils
    ]}
    exec ${pkgs.python3}/bin/python3 -u ${pkgs.writeText "apparmor-gui-backend.py" (builtins.readFile ./apparmor-gui-backend.py)} "$@"
  '';

  app = pkgs.stdenv.mkDerivation {
    pname = "apparmor-gui";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.wrapGAppsHook4 ];
    buildInputs = [
      pythonEnv
      pkgs.gtk4
      pkgs.libadwaita
      pkgs.gobject-introspection
      pkgs.adwaita-icon-theme
    ];
    installPhase = ''
      mkdir -p $out/bin $out/share/apparmor-gui
      cp ${./apparmor-gui.py} $out/share/apparmor-gui/apparmor-gui.py
      cat > $out/bin/apparmor-gui <<EOF
#!/bin/sh
exec ${pythonEnv}/bin/python3 $out/share/apparmor-gui/apparmor-gui.py
EOF
      chmod +x $out/bin/apparmor-gui
    '';
  };

  desktop = pkgs.makeDesktopItem {
    name = "apparmor-gui";
    desktopName = "AppArmor";
    comment = "Profiles, services, applications, and AppArmor commands";
    exec = "apparmor-gui";
    icon = "security-high";
    categories = [ "System" "Security" ];
    startupNotify = true;
  };
in
{
  environment.systemPackages = [
    app
    backend
    desktop
    pkgs.apparmor-utils
    pkgs.apparmor-parser
  ];

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.policykit.exec" &&
          action.lookup("command") &&
          action.lookup("command").indexOf("apparmor-gui-backend") !== -1 &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
}
