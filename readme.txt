Scott's Modifications to Maccasoft VGA Serial Terminal
======================================================

This is my fork of https://www.maccasoft.com/electronics/vga-serial-terminal/ to add whatever
features are useful for me for my vintage computer projects.

When in doubt, you should probably use the original source as I may customize things here
without explanation and in a non-portable way.

Changes include:

* Added a 7-bit mode, which strips the MSB from incoming characters. This supports some (but not all)
  vintage computers that use 7E1 or 7E2 parity.

* Added some kind of additional scrolling stuff. Maybe for the H8?? I don't remember...

Propeller VGA Terminal Firmware
===============================

terminal_720x400_ps2.eeprom.bin - 64k EEPROM binary for PS/2 keyboard
terminal_720x400_usb.eeprom.bin - 64k EEPROM binary for USB keyboard

Build
-----

The provided Python script build.py performs the necessary operations to build
the firmware binaries from the spin source code. Requires the openspin 1.00.81
(or grater) compiler.
