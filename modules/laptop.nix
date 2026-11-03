#laptop.nix

{ config, pkgs, lib, ... }:

{

  services.fstrim.enable = true;
  services.power-profiles-daemon.enable = true;
  services.fwupd.enable = true;

  nix.optimise.automatic = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

}
