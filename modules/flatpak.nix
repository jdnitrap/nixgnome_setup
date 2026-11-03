#flatpak.nix

{ config, lib, pkgs, ... }:

{
  services.flatpak.enable = true;

  # System installs. Available to every account.
  systemd.services.flatpak-system-apps = {
    description = "Install system Flatpaks from Flathub";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig.Type = "oneshot";
    script = ''
      flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install --system --noninteractive --assumeyes flathub app.zen_browser.zen org.mozilla.firefox
    '';
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.Flatpak.app-update" ||
          action.id == "org.freedesktop.Flatpak.runtime-update") {
        return polkit.Result.YES;
      }

      # GNOME Software metadata refresh.
      if (action.id == "org.freedesktop.packagekit.system-sources-refresh" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }

      if (action.id.indexOf("org.freedesktop.Flatpak.") == 0) {
        if (subject.isInGroup("wheel")) {
          return polkit.Result.AUTH_ADMIN_KEEP;
        }
        return polkit.Result.NO;
      }
    });
  '';
}
