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

  # The Extensions command ships inside GNOME Shell. Refuse it for every account.
  # Software and Settings stay in the app grid. Other system launchers are
  # hidden, and their panels stay inside Settings.
  environment.systemPackages = [
    (lib.hiPrio (pkgs.runCommand "gnome-extensions-disabled" { } ''
      mkdir -p $out/bin $out/share/dbus-1/services
      cat > $out/bin/gnome-extensions-app <<'EOF'
#!/bin/sh
echo "The Extensions app is disabled." >&2
exit 1
EOF
      chmod 0555 $out/bin/gnome-extensions-app
      cat > $out/share/dbus-1/services/org.gnome.Extensions.service <<EOF
[D-BUS Service]
Name=org.gnome.Extensions
Exec=$out/bin/gnome-extensions-app
EOF
    ''))

    (lib.hiPrio (pkgs.runCommand "gnome-grid-software-only" {
      paths = with pkgs; [
        gnome-shell
        gnome-control-center
        gnome-software
        gnome-color-manager
        gnome-remote-desktop
        gnome-browser-connector
        gnome-initial-setup
        gnome-bluetooth
        gnome-keyring
        gnome-settings-daemon
        gnome-session
        orca
        ibus
        rygel
        xdg-user-dirs-gtk
        system-config-printer
      ];
    } ''
      mkdir -p "$out/share/applications"
      for p in $paths; do
        dir="$p/share/applications"
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
          [ -e "$f" ] || continue
          base=$(basename "$f")
          case "$base" in
            org.gnome.Software.desktop|org.gnome.Settings.desktop) continue ;;
          esac
          awk '
            /^\[Desktop Entry\]/ { print; print "NoDisplay=true"; print "Hidden=true"; next }
            /^NoDisplay=/ || /^Hidden=/ { next }
            { print }
          ' "$f" > "$out/share/applications/$base"
        done
      done
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