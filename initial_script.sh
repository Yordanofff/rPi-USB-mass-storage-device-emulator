#!/bin/bash

# More info: 
# https://github.com/Yordanofff/rPi-USB-mass-storage-device-emulator/
# Todo: The service doesn't work at all if the ExecStop script is uncommented. Run it manually if needed.


# Check if the user running the script is root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please use sudo or run as root user."
    exit 1
fi

# Pause the script to allow cancellation.
read -r -p $'\nThe script is starting.. \nPress any key to continue or [Ctrl + C] to stop the execution. \n'

########################################################################
# Create the folder where all files will be placed (Except the service file)
########################################################################
SCRIPTS_FOLDER_LOCATION="/scripts"
if [ ! -e "$SCRIPTS_FOLDER_LOCATION" ]; then
	mkdir "$SCRIPTS_FOLDER_LOCATION"
fi

########################################################################
# Kernel stuff - load modules that allow/support USB OTG host/gadget
########################################################################

# Function to check and append lines to a file if they don't exist
check_and_append_line() {
    local file_path="$1"
    local line_to_append="$2"

    # Check if the line already exists in the file
    if grep -qF "$line_to_append" "$file_path"; then
		echo "Line \"$line_to_append\" already in \"$file_path\"."
	else
		# Append the line only if it doesn't exist
        echo "$line_to_append" | sudo tee -a "$file_path"
        echo "Line \"$line_to_append\" appended successfully to \"$file_path\"."
    fi
}

# Function to create backup file if the backup file doesn't already exist
create_backup() {
    local file_path="$1"
    local backup_file="${file_path}.backup"

    if [ ! -f "$backup_file" ]; then
        cp "$file_path" "$backup_file"
        echo "Backup created for \"$file_path\" as \"$backup_file\"."
    else
        echo "Backup already exists for \"$file_path\". Skipping backup creation."
    fi
}

# Array to store file paths and lines to append
files_and_lines=(
    "/etc/modules:dwc2"
    "/etc/modules:libcomposite"
	"/boot/config.txt:dtoverlay=dwc2"
)

# Loop through the array and call the functions for each entry
for item in "${files_and_lines[@]}"; do
    file_path="${item%%:*}"
    line_to_append="${item##*:}"
	
	create_backup "$file_path"
    check_and_append_line "$file_path" "$line_to_append"
done

# Load the g_mass_storage kernel module if not loaded. /sys/kernel/config/usb_gadget/ should exist.
USB_GADGET_FILE_LOCATION="/sys/kernel/config/usb_gadget/"
if [ ! -e "$USB_GADGET_FILE_LOCATION" ]; then
	echo "$USB_GADGET_FILE_LOCATION is missing. Loading the \"g_mass_storage\" kernel module.."
	modprobe g_mass_storage
fi

if [ ! -e "$USB_GADGET_FILE_LOCATION" ]; then
	echo -e "ERROR: $USB_GADGET_FILE_LOCATION is still missing. \nTry loading the kernel module manually using \"modprobe g_mass_storage\".\nCheck if loadead using \"lsmod | grep g_mass_storage\""
	exit 1
else
	echo "Kernel module loaded successfully."
fi

########################################################################
# Create disk image to be used as a mass storage.
# Will not re-create the file if it already exists to protect data deletion.
########################################################################
DISK_FILE_NAME="usb_disk.img"
DISK_FILE_LOCATION="$SCRIPTS_FOLDER_LOCATION/$DISK_FILE_NAME"
DISK_BLOCK_SIZE_IN_BYTES=1024
DISK_SIZE_IN_MB=100

if [ -e "$DISK_FILE_LOCATION" ]; then
	echo "Disk dile already exists and won't be recreated - \"$DISK_FILE_LOCATION\""
	echo "Get the data out and delete the file manually (rm $DISK_FILE_LOCATION) if you wish to re-create it."
else
	echo "Disk file doesn't exist and will be created at \"$DISK_FILE_LOCATION\""
	
	# Disk size = block size * num blocks. /1024*1024 = 1MB/
	DISK_NUMBER_OF_BLOCKS=$(("$DISK_SIZE_IN_MB"*1024*1024/"$DISK_BLOCK_SIZE_IN_BYTES"))
	
	dd if=/dev/zero of="$DISK_FILE_LOCATION" bs="$DISK_BLOCK_SIZE_IN_BYTES" count="$DISK_NUMBER_OF_BLOCKS"
	mkdosfs "$DISK_FILE_LOCATION"
	
	echo "Disk file created. Size: $DISK_SIZE_IN_MB Mb. Block size: $DISK_BLOCK_SIZE_IN_BYTES bytes."
fi


########################################################################
# Create the script and populate it - it will run on every system boot
########################################################################
START_SCRIPT_NAME="start_script"
START_SCRIPT_FULL_PATH="$SCRIPTS_FOLDER_LOCATION/$START_SCRIPT_NAME"


MASS_SERIAL="1122334455xyz"
MASS_MANUFACTURE="JetFlash"
MASS_PRODUCT=""  #"Mass Storage" # Device Name
MASS_CONFIG="Config 1: Mass Storage"

MASS_VENDOR_ID="8564"  # 0x will be added to the beginning
MASS_PRODUCT_ID="1000"  # 0x will be added to the beginning
MASS_DESCRIPTION="JetFlash"  # The device will show up as "Linux File-Stor Gadget" if this is not set.


# Create the script file and make it executable if it doesn't exist (first run)
if [ ! -e "$START_SCRIPT_FULL_PATH" ]; then
	touch "$START_SCRIPT_FULL_PATH"
	chmod +x "$START_SCRIPT_FULL_PATH" #make it executable
fi

# Populate the script and save it
cat <<EOF > "$START_SCRIPT_FULL_PATH"
#!/bin/bash

# This script will be run on every system boot by a service
# Can be modified and run manually again - you'll need to run the stop script first.
# Any changes made to this script will remain the same after a reboot


# Check if the user running the script is root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please use sudo or run as root user."
    exit 1
fi

if [ ! -e "$USB_GADGET_FILE_LOCATION" ]; then
	echo -e "ERROR: $USB_GADGET_FILE_LOCATION is still missing. \nTry loading the kernel module manually using \"modprobe g_mass_storage\".\nCheck if loadead using \"lsmod | grep g_mass_storage\""
	exit 1
fi

cd "$USB_GADGET_FILE_LOCATION"
mkdir -p usbstick
cd usbstick
echo 0x$MASS_VENDOR_ID  > idVendor
echo 0x$MASS_PRODUCT_ID > idProduct

echo 0x0100 			  > bcdDevice # v1.0.0
echo 0x0200 			  > bcdUSB 	  # USB2
mkdir -p strings/0x409
echo "$MASS_SERIAL" 	  > strings/0x409/serialnumber
echo "$MASS_MANUFACTURE"  > strings/0x409/manufacturer
echo "$MASS_PRODUCT" 	  > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "$MASS_CONFIG" 	  > configs/c.1/strings/0x409/configuration
echo 250 				  > configs/c.1/MaxPower

# Add functions here /Mass storage, HID, Ethernet Adapter, Serial Adapter.../

# Mass storage
mkdir -p "${DISK_FILE_LOCATION/img/d}"
mount -o loop,ro, -t vfat "$DISK_FILE_LOCATION" "${DISK_FILE_LOCATION/img/d}" # FOR IMAGE CREATED WITH DD
mkdir -p functions/mass_storage.usb0
echo 1 > functions/mass_storage.usb0/stall
echo 0 > functions/mass_storage.usb0/lun.0/cdrom
echo 0 > functions/mass_storage.usb0/lun.0/ro
echo 0 > functions/mass_storage.usb0/lun.0/nofua
echo "$DISK_FILE_LOCATION" > functions/mass_storage.usb0/lun.0/file
echo "$MASS_DESCRIPTION" > functions/mass_storage.usb0/lun.0/inquiry_string
ln -s functions/mass_storage.usb0 configs/c.1/

# End functions

ls /sys/class/udc > UDC
EOF

########################################################################
# Create stop script - will unmount the device (not safe) from PC, so the USB details 
# can be changed and the start script can be re-run without restarting the rPi
########################################################################
STOP_SCRIPT_NAME="stop_script"
STOP_SCRIPT_FULL_PATH="$SCRIPTS_FOLDER_LOCATION/${STOP_SCRIPT_NAME}"

# Create the script file and make it executable if it doesn't exist (first run)
if [ ! -e "$STOP_SCRIPT_FULL_PATH" ]; then
	touch "$STOP_SCRIPT_FULL_PATH"
	chmod +x "$STOP_SCRIPT_FULL_PATH" #make it executable
fi

cat <<EOF > "$STOP_SCRIPT_FULL_PATH"
#!/bin/bash

# This script will force unmount the mass storage device from the computer (NOT safe removal - 
# any data transfers will fail and data may become corrupted.) 
# 
# To be run when changes to the USB drive description are needed (to be made in the start script)
# 
# No data in the usb drive (img file) will be lost - so the "new" device will have the "old" data.


# Check if the user running the script is root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please use sudo or run as root user."
    exit 1
fi

cd "$USB_GADGET_FILE_LOCATION"

echo "" > usbstick/UDC
rm usbstick/configs/c.1/mass_storage.usb0
rmdir usbstick/configs/c.1/strings/0x409/
rmdir usbstick/configs/c.1/
rmdir usbstick/functions/mass_storage.usb0/
rmdir usbstick/strings/0x409/
rmdir usbstick/

umount "${DISK_FILE_LOCATION/img/d}"

EOF


########################################################################
# Create a service to start the script
########################################################################

# Create the service file if it doesn't exist (first run)
SERVICE_NAME="my_service.service"
SERVICE_FILE_LOCATION="/etc/systemd/system/$SERVICE_NAME"
if [ ! -e "$SERVICE_FILE_LOCATION" ]; then
	touch "$SERVICE_FILE_LOCATION"
fi

# Populate the service:
cat <<EOF > "$SERVICE_FILE_LOCATION"
[Unit]
Description=Starts the script that emulates the USB mass storage device.
After=network.target

[Service]
Type=simple
User=root
ExecStart=$START_SCRIPT_FULL_PATH
#ExecStop=$STOP_SCRIPT_FULL_PATH       
RemainAfterExit=true                   # Keep the service active after the main process exits

[Install]
WantedBy=multi-user.target
EOF

systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
echo "Service: \"$SERVICE_NAME\" created at \"$SERVICE_FILE_LOCATION\" and enabled/started."

read -p "Reboot required. Do you want to reboot now? (y/n): " choice

if [[ $choice == "y" || $choice == "Y" ]]; then
    reboot
else
    echo "\"$choice\" entered. Please reboot the system manually."
fi
