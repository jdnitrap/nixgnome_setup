#bootloader.nix

{config, pkgs, lib, ...}:

{

	# Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Keep the boot menu short. Older generations are dropped from the menu.
  boot.loader.systemd-boot.configurationLimit = 5;

  # Splash after the generation menu. Hides the boot text.
  boot.plymouth.enable = true;
  boot.plymouth.theme = "circuit";
  boot.plymouth.themePackages = [
    (pkgs.adi1090x-plymouth-themes.override {
      selected_themes = [ "circuit" ];
    })
  ];

  # Quiet the rundown so the splash is what you see.
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "rd.systemd.show_status=auto"
    "rd.udev.log_level=3"
  ];

}
