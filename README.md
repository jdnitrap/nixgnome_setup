# nixgnome_setup

NixOS GNOME configuration, split into modules under `modules/`.

This is not a flake. After you clone it, replace `networking.hostName` in `configuration.nix`. Generate `hardware-configuration.nix` with `nixos-generate-config` and leave that file on the machine.
