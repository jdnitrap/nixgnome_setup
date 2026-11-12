#dns-lock.nix
# Force outbound DNS through AdGuard. Port 53 may go to localhost, or leave
# the machine only as the adguardhome user (its plain-DNS fallback). Port 853
# (DNS-over-TLS) is refused. HTTPS is left to each program.

{ pkgs, ... }:

let
  # Immediate, offline undo. A firewall reload or reboot puts the lock back.
  # Lasting undo from the local keyboard: run0 nixos-rebuild switch --rollback
  restore-network = pkgs.writeShellScriptBin "restore-network" ''
    systemctl stop mitmproxy-redirect.service 2>/dev/null || true
    systemctl stop mitmproxy.service 2>/dev/null || true
    systemctl stop opensnitchd.service 2>/dev/null || true
    iptables -w -t nat -D OUTPUT -j nixos-tls-proxy 2>/dev/null || true
    iptables -w -t nat -F nixos-tls-proxy 2>/dev/null || true
    iptables -w -t nat -X nixos-tls-proxy 2>/dev/null || true
    iptables -w -D OUTPUT -j nixos-quic-reject 2>/dev/null || true
    iptables -w -F nixos-quic-reject 2>/dev/null || true
    iptables -w -X nixos-quic-reject 2>/dev/null || true
    iptables -w -D OUTPUT -j nixos-dns-lock 2>/dev/null || true
    iptables -w -F nixos-dns-lock 2>/dev/null || true
    iptables -w -X nixos-dns-lock 2>/dev/null || true
    ip6tables -w -D OUTPUT -j nixos-dns-lock 2>/dev/null || true
    ip6tables -w -F nixos-dns-lock 2>/dev/null || true
    ip6tables -w -X nixos-dns-lock 2>/dev/null || true
    echo "Proxy redirect, OpenSnitch, and the DNS lock are off until reboot or the next firewall start."
    echo "Lasting undo, from this keyboard, with no network: run0 nixos-rebuild switch --rollback"
    echo "Or pick the previous generation in the boot menu."
  '';
in
{
  environment.systemPackages = [ restore-network ];

  networking.firewall.extraCommands = ''
    iptables -w -N nixos-dns-lock 2>/dev/null || true
    iptables -w -F nixos-dns-lock
    iptables -w -A nixos-dns-lock -o lo -j RETURN
    iptables -w -A nixos-dns-lock -m owner --uid-owner adguardhome -p udp --dport 53 -j RETURN
    iptables -w -A nixos-dns-lock -m owner --uid-owner adguardhome -p tcp --dport 53 -j RETURN
    iptables -w -A nixos-dns-lock -p udp --dport 53 -j REJECT
    iptables -w -A nixos-dns-lock -p tcp --dport 53 -j REJECT
    iptables -w -A nixos-dns-lock -p udp --dport 853 -j REJECT
    iptables -w -A nixos-dns-lock -p tcp --dport 853 -j REJECT
    iptables -w -C OUTPUT -j nixos-dns-lock 2>/dev/null || iptables -w -A OUTPUT -j nixos-dns-lock

    ip6tables -w -N nixos-dns-lock 2>/dev/null || true
    ip6tables -w -F nixos-dns-lock
    ip6tables -w -A nixos-dns-lock -o lo -j RETURN
    ip6tables -w -A nixos-dns-lock -m owner --uid-owner adguardhome -p udp --dport 53 -j RETURN
    ip6tables -w -A nixos-dns-lock -m owner --uid-owner adguardhome -p tcp --dport 53 -j RETURN
    ip6tables -w -A nixos-dns-lock -p udp --dport 53 -j REJECT
    ip6tables -w -A nixos-dns-lock -p tcp --dport 53 -j REJECT
    ip6tables -w -A nixos-dns-lock -p udp --dport 853 -j REJECT
    ip6tables -w -A nixos-dns-lock -p tcp --dport 853 -j REJECT
    ip6tables -w -C OUTPUT -j nixos-dns-lock 2>/dev/null || ip6tables -w -A OUTPUT -j nixos-dns-lock
  '';

  networking.firewall.extraStopCommands = ''
    iptables -w -D OUTPUT -j nixos-dns-lock 2>/dev/null || true
    iptables -w -F nixos-dns-lock 2>/dev/null || true
    iptables -w -X nixos-dns-lock 2>/dev/null || true
    ip6tables -w -D OUTPUT -j nixos-dns-lock 2>/dev/null || true
    ip6tables -w -F nixos-dns-lock 2>/dev/null || true
    ip6tables -w -X nixos-dns-lock 2>/dev/null || true
  '';
}
