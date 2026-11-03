#adguard.nix

{ config, pkgs, lib, ... }:

{

  # Local DNS blocker. Covers every app that uses the system DNS.
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    mutableSettings = true;

    settings = {
      dns = {
        bind_hosts = [
          "127.0.0.1"
          "::1"
        ];
        port = 53;
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
        ];
        fallback_dns = [
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
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
        {
          enabled = true;
          id = 2;
          name = "AdGuard DNS popup filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_59.txt";
        }
        {
          enabled = true;
          id = 3;
          name = "Malicious URL Blocklist (URLHaus)";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt";
        }
        {
          enabled = true;
          id = 4;
          name = "Dandelion Sprout's Anti-Malware List";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt";
        }
        {
          enabled = true;
          id = 5;
          name = "Phishing URL Blocklist (PhishTank and OpenPhish)";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_30.txt";
        }
        {
          enabled = true;
          id = 6;
          name = "NoCoin Filter List";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt";
        }
      ];

      # Public resolver names only. A browser that cannot open its own
      # secure DNS falls back to this machine's DNS. VPN, Tor, and proxy
      # services are not listed here.
      user_rules = [
        "||dns.google^"
        "||dns.google.com^"
        "||dns.quad9.net^"
        "||dns9.quad9.net^"
        "||dns10.quad9.net^"
        "||dns11.quad9.net^"
        "||dns12.quad9.net^"
        "||dns.cloudflare.com^"
        "||cloudflare-dns.com^"
        "||one.one.one.one^"
        "||dns.nextdns.io^"
        "||dns.adguard-dns.com^"
        "||doh.opendns.com^"
        "||dns.opendns.com^"
        "||dns.cleanbrowsing.org^"
        "||doh.cleanbrowsing.org^"
        "||dns.switch.ch^"
      ];
    };
  };

  # Point the system at the local blocker.
  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];
  networking.networkmanager.dns = "none";

}
