#gnome.nix

{ config, pkgs, lib, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.gnome.core-apps.enable = false;
  services.gnome.core-developer-tools.enable = false;
  services.gnome.games.enable = false;

  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    gnome-user-docs
    gnome-shell-extensions
  ];

  # The Extensions icon and command ship inside GNOME Shell. Hide the
  # launcher and put a refusal in front of the command for every account.
  environment.systemPackages = [
    (lib.hiPrio (pkgs.runCommand "gnome-extensions-disabled" { } ''
      mkdir -p $out/bin $out/share/applications $out/share/dbus-1/services
      cat > $out/bin/gnome-extensions-app <<'EOF'
#!/bin/sh
echo "The Extensions app is disabled." >&2
exit 1
EOF
      chmod 0555 $out/bin/gnome-extensions-app
      cat > $out/share/applications/org.gnome.Extensions.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Extensions
NoDisplay=true
Hidden=true
EOF
      cat > $out/share/dbus-1/services/org.gnome.Extensions.service <<EOF
[D-BUS Service]
Name=org.gnome.Extensions
Exec=$out/bin/gnome-extensions-app
EOF
    ''))
  ];

  # GNOME hides Log Out with one account and one session. Show it anyway.
  programs.dconf.profiles.user.databases = [{
    settings."org/gnome/shell".always-show-log-out = true;
  }];

  # Trash, mounts, and network locations for any file manager.
  services.gvfs.enable = true;

  # FileChooser portal does not require Nautilus. GTK backend works with other managers
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.gnome = {
      default = [ "gnome" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
    };
  };

  # Terminal=true desktop files and GLib terminal launches use this instead of Console.
  xdg.terminal-exec.enable = true;
}