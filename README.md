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

Semi-auto steps:
Enter this and **paste** the content of the script in the text window. (To save and exit use **[Ctrl + X] -> Y -> Enter**)
The script will start automatically and will ask the user to continue the execution or to stop it.

**sudo mkdir /scripts && cd "$\_" && sudo touch initial_script.sh && sudo chmod +x "$\_" && sudo nano "$\_" && sudo /scripts/"$\_"**


Manual steps:
1. Copy thе script on the device
2. Make it executable using
3. Run the script as root
4. Reboot the rPi at the end
   
