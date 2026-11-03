#printer-scanner.nix

{ config, pkgs, lib, ... }:

{

# Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.browsing = true;
  programs.system-config-printer.enable = true;
  services.system-config-printer.enable = true;
  services.avahi = {
  enable = true;
  nssmdns4 = true;
  openFirewall = true;
};

services.printing.drivers = with pkgs; [
	gutenprint
	gutenprintBin
	epson-escpr2
	epson-escpr
	];

hardware.sane.enable = true; # enables support for SANE scanners
  services.ipp-usb.enable = true;

}
