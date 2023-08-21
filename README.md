# This script can be used to emulate a rPi as another USB flash drive (mass storage device).

# USE AT YOUR OWN RISK

Only tested on **Raspberry Pi Zero W** - running **Raspberry Pi OS Lite(32-bit) - _A port of Debian Bullseye with no desktop environment /0.4GB/_**

You will be able to clone/modify the:
- Serial number
- Manufacturer
- Product name
- Vendor ID
- Product ID
- Device Description

Modify the script to your own needs. Default storage/image size - 100MB



Easiest way to run the script:

**sudo mkdir /scripts && cd "$\_" && sudo wget https://raw.githubusercontent.com/Yordanofff/rPi-USB-mass-storage-device-emulator/main/initial_script.sh && sudo chmod +x $(basename "$\_") && sudo /scripts/"$\_"**


**NirSoft USBDeview** can be used to check all attributes of a USB device. For each USB device, extended information is displayed: Device name/description, device type, serial number (for mass storage devices), the date/time that device was added, VendorID, ProductID, and more... https://www.nirsoft.net/utils/usb_devices_view.html
