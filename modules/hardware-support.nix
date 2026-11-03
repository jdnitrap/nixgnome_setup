#hardware-support.nix

{ config, pkgs, lib, ... }:

{

  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # GNOME uses this to mount USB drives without a password.
  services.udisks2.enable = true;

  # Common external drive formats.
  boot.supportedFilesystems = [ "ntfs" "exfat" ];

}
