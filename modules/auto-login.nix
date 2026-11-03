#auto-login.nix

{ config, pkgs, lib, ... }:

{
  services.accounts-daemon.enable = true;
  users.mutableUsers = true;
}
