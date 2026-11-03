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