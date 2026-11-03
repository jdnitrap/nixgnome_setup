#configuration.nix

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/hardware-support.nix
    ./modules/printer-scanner.nix
    ./modules/system-setup.nix
    ./modules/sound.nix
    ./modules/state-version.nix
    ./modules/system-packages.nix
    ./modules/gnome.nix
    ./modules/boot.nix
    ./modules/networking.nix
    ./modules/bluetooth.nix
    ./modules/user-accounts.nix
    ./modules/flatpak.nix
    ./modules/auto-update.nix
    ./modules/experimental-features.nix
    ./modules/laptop.nix
    ./modules/apparmor.nix
    ./modules/apparmor-gui.nix
    ./modules/adguard.nix
  ];

  # Replace this after you clone the repo onto a machine.
  networking.hostName = "hostname";

  # hardware-configuration.nix stays on the machine.

  # GNOME stays the default login session.
  services.displayManager.defaultSession = lib.mkForce "gnome";

  # GNOME gets the SSH password prompt.
  programs.ssh.askPassword = lib.mkForce "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
}
