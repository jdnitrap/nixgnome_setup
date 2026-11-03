#flatpak.nix

{ config, lib, pkgs, ... }:

{
  services.flatpak.enable = true;

  # User installs only. Each account gets its own Flathub remote.
  systemd.user.services.flatpak-user-repo = {
    description = "Add Flathub remote for the user";
    wantedBy = [ "default.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig.Type = "oneshot";
    script = ''
      flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

  systemd.user.services.flatpak-user-update = {
    description = "Update user Flatpaks";
    after = [ "network-online.target" "flatpak-user-repo.service" ];
    wants = [ "network-online.target" "flatpak-user-repo.service" ];
    path = [ pkgs.flatpak ];
    serviceConfig.Type = "oneshot";
    script = "flatpak update --user --noninteractive --assumeyes";
  };

  systemd.user.timers.flatpak-user-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.Flatpak.app-update" ||
           action.id == "org.freedesktop.Flatpak.runtime-update") &&
          subject.active && subject.local && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }

      # GNOME Software metadata refresh.
      if (action.id == "org.freedesktop.packagekit.system-sources-refresh" &&
          subject.active && subject.local && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }

      if (action.id.indexOf("org.freedesktop.Flatpak.") == 0) {
        if (subject.active && subject.local && subject.isInGroup("wheel")) {
          return polkit.Result.AUTH_ADMIN_KEEP;
        }
        return polkit.Result.NO;
      }
    });
  '';
}
