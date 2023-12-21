#!/usr/bin/python3

import os
import sys
import datetime

import zipfile

#toolchain = "/opt/parallax/bin/"
toolchain = "/usr/local/bin/"
branch = "terminal"

# Common keyboard maps

os.system(toolchain + "openspin -b -o keyboard_maps.binary -c keyboard_maps.spin")
src = open("keyboard_maps.binary", "rb");
maps_data = src.read()
src.close()

# USB

target = branch + "_720x400_usb"
eeprom = bytearray(32768)

print("")
os.system(toolchain + "openspin -b -u -DKB_USB -o " + target + ".binary terminal.spin")
src = open(target + ".binary", "rb");
data = src.read()
src.close()

eeprom[0x0000:0x0000 + len(data)] = data
eeprom[0x6000:0x6000 + len(maps_data)] = maps_data

dst = open(target + ".eeprom.bin", "wb")
dst.write(eeprom)
dst.close()

# PS/2

target = branch + "_720x400_ps2"
eeprom = bytearray(32768)

print("")
os.system(toolchain + "openspin -b -u -DKB_PS2 -o " + target + ".binary terminal.spin")
src = open(target + ".binary", "rb");
data = src.read()
src.close()

eeprom[0x0000:0x0000 + len(data)] = data
eeprom[0x6000:0x6000 + len(maps_data)] = maps_data

dst = open(target + ".eeprom.bin", "wb")
dst.write(eeprom)
dst.close()

