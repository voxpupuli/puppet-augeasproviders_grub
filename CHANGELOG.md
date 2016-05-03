# Changelog

## 2.4.0

- Add support for global GRUB configuration
- Add support for grub_menuentry providing the ability to manage individual
  menu entries for both GRUB Legacy and GRUB2
- Add support for managing GRUB2 users
- The following custom types were created:
  * grub_config :  Manages global GRUB settings
  * grub_menuentry : Manages GRUB menuentries
  * grub_user : Manages GRUB2 users
- Confine GRUB providers to presence of menus, prefer GRUB 2 (#8)
- Fix build on Ruby 1.8

## 2.3.0

- Fix GRUB_CMDLINE_LINUX_DEFAULT (issue #14)
- Add grub.cfg location for UEFI systems (issue #16)
- Add two defaults in grub2 provider (issue #17)

## 2.2.0

- Add support for bootmode 'default' (issue #3)

## 2.1.0

- Set default to grub2 provider on el7 based systems (fix #9)
- Load lenses from lib/augeas/lenses in tests
- Add Puppet 4 to test matrix

## 2.0.1

- Fix metadata.json
- Various minor updates to Travis test configuration

## 2.0.0

- First release of split module.
