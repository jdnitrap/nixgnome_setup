#auto-update.nix

{ config, pkgs, lib, ... }:

{
  system.autoUpgrade = {
    enable = true;
    persistent = true;
    dates = "19:00";
    randomizedDelaySec = "0";
    allowReboot = false;
    flags = [
      "--upgrade"
      "--option" "build-cores" "1"
      "--option" "cores" "1"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  systemd.services.nixos-upgrade = {
    path = [ pkgs.libnotify pkgs.sudo pkgs.coreutils ];
    serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
    postStart = ''
      for uid in $(ls /run/user 2>/dev/null || true); do
        [ -S "/run/user/$uid/bus" ] || continue
        user=$(id -nu "$uid" 2>/dev/null || true)
        [ -n "$user" ] || continue
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          notify-send "NixOS update" "The 7 PM system update finished." || true
      done
    '';
  };
}
