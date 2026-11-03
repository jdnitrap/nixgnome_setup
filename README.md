# nixgnome_setup

NixOS GNOME configuration, split into modules under `modules/`.

This is not a flake. On the machine, set `networking.hostName` in `configuration.nix`. Generate `hardware-configuration.nix` with `nixos-generate-config` and leave that file on the machine.
