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
}
