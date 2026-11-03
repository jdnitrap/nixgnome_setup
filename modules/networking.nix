#networking.nix

{config, pkgs, lib, ...}:

{

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = false;

  # NixOS firewall.
  networking.firewall.enable = true;
  # Loose mode keeps a VPN working. Packets that match no route are still dropped.
  networking.firewall.checkReversePath = "loose";

}
