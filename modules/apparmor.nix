#apparmor.nix

{ config, pkgs, lib, ... }:

{
  security.apparmor.enable = true;
  security.apparmor.killUnconfinedConfinables = false;

  # Complain mode logs denials without blocking. Switch to enforce after the logs are quiet.
  security.apparmor.policies = {
    "usr.sbin.avahi-daemon" = {
      state = "complain";
      profile = ''
        include <tunables/global>
        profile avahi-daemon ${pkgs.avahi}/bin/avahi-daemon flags=(attach_disconnected) {
          include <abstractions/base>
          include <abstractions/nameservice>
          include <abstractions/dbus>
          capability net_bind_service,
          capability chown,
          capability setuid,
          capability setgid,
          network inet dgram,
          network inet6 dgram,
          network netlink dgram,
          /etc/avahi/ r,
          /etc/avahi/** r,
          /run/avahi-daemon/ rw,
          /run/avahi-daemon/** rw,
          /run/systemd/notify w,
        }
      '';
    };

    "usr.sbin.cupsd" = {
      state = "complain";
      profile = ''
        include <tunables/global>
        profile cupsd ${pkgs.cups}/bin/cupsd flags=(attach_disconnected) {
          include <abstractions/base>
          include <abstractions/nameservice>
          include <abstractions/dbus>
          capability chown,
          capability dac_override,
          capability setuid,
          capability setgid,
          network inet stream,
          network inet dgram,
          /etc/cups/ r,
          /etc/cups/** r,
          /var/log/cups/ rw,
          /var/log/cups/** rw,
          /var/spool/cups/ rw,
          /var/spool/cups/** rw,
          /run/cups/ rw,
          /run/cups/** rw,
        }
      '';
    };

    "usr.sbin.bluetoothd" = {
      state = "complain";
      profile = ''
        include <tunables/global>
        profile bluetoothd ${pkgs.bluez}/libexec/bluetooth/bluetoothd flags=(attach_disconnected) {
          include <abstractions/base>
          include <abstractions/dbus>
          capability net_admin,
          capability net_bind_service,
          network bluetooth,
          /etc/bluetooth/ r,
          /etc/bluetooth/** r,
          /var/lib/bluetooth/ rw,
          /var/lib/bluetooth/** rw,
          /run/bluetooth/ rw,
          /run/bluetooth/** rw,
        }
      '';
    };
  };
}
