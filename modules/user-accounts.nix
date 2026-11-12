#user-accounts.nix

{config, lib, pkgs, inputs, ... }:

{
  users.mutableUsers = true;

  users.users.Admin = {
    isNormalUser = true;
    description = "Admin";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    initialPassword = "changeme";
  };

  users.users.John = {
    isNormalUser = true;
    description = "John";
    uid = 1002;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };
}
