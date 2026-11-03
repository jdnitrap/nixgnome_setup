#adguard.nix

{ config, pkgs, lib, ... }:

{

  # Local DNS blocker. Covers every app on this machine.
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    mutableSettings = true;

    settings = {
      dns = {
        bind_hosts = [ "127.0.0.1" ];
        port = 53;
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "https://dns.cloudflare.com/dns-query"
        ];
        bootstrap_dns = [
          "9.9.9.9"
          "1.1.1.1"
        ];
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        parental_enabled = false;
        safe_search.enabled = false;
      };

      filters = [
        {
          enabled = true;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
        {
          enabled = true;
          name = "AdGuard DNS popup filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_59.txt";
        }
      ];
    };
  };

  # Point the system at the local blocker.
  networking.nameservers = [ "127.0.0.1" ];
  networking.networkmanager.dns = "none";

}
