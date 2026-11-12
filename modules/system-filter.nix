#system-filter.nix
# OpenSnitch watches outbound programs. Unknown programs are allowed until
# the OpenSnitch window is open, so a missed prompt cannot drop the network.
# The HTTPS proxy was removed: programs such as Red trust their own
# certificates and refuse a local stand-in.

{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.opensnitch-ui ];

  services.opensnitch = {
    enable = true;
    settings = {
      ProcMonitorMethod = "proc";
      Firewall = "iptables";
      DefaultAction = "allow";
      InterceptUnknown = true;
      LogLevel = 1;
    };
  };
}
