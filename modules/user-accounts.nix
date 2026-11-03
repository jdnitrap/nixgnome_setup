#user-accounts.nix

{config, lib, pkgs, inputs, ... }:

{
  users.mutableUsers = true;

  users.users.admin = {
    isNormalUser = true;
    description = "Admin";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };
}
