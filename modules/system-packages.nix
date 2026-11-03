#system-package.nix

{config, pkgs, lib, ...}:

{

 # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  
  environment.systemPackages = with pkgs; [

	git
	gnome-software
	gh
	flatpak
	wireguard-tools

	];



}
