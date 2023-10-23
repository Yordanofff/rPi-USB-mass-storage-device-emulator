#!/bin/bash

# More info:
# https://github.com/Yordanofff/rPi-USB-mass-storage-device-emulator/
# Todo: The service doesn't work at all if the ExecStop script is uncommented. Run it manually if needed.

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }

# Check if the user running the script is root
if [ "$EUID" -ne 0 ]; then
    warn "ERROR: This script must be run as root. Please use sudo or run as root user."
    exit 1
fi

# Pause the script to allow cancellation.
echo "==== RPi Thumb Drive Emulation Script ===="
echo "This script is designed to emulate your Raspberry Pi as a USB Thumb Drive."
echo "It will create an image file using the details from the settings.conf configuration."
echo "As part of the process, a Samba server will be installed to facilitate data transfers via the SMB protocol."
echo "All generated files will be stored in the /scripts directory."
warn "Check the /scripts/settings.conf file before continuing!"
read -r -p $'\nPress any key to continue or [Ctrl + C] to stop the execution. \n'

########################################################################
# Create the folder where all files will be placed (Except the service file)
########################################################################
# Read variables from file
source ./settings.conf

if [ ! -e "$SCRIPTS_FOLDER_LOCATION" ]; then
    mkdir "$SCRIPTS_FOLDER_LOCATION"
fi

DISK_FILE_LOCATION="$SCRIPTS_FOLDER_LOCATION/$DISK_FILE_NAME"
DISK_MNT_LOCATION="$SCRIPTS_FOLDER_LOCATION/$DISK_MNT_NAME"
START_SCRIPT_FULL_PATH="$SCRIPTS_FOLDER_LOCATION/$START_SCRIPT_NAME"
STOP_SCRIPT_FULL_PATH="$SCRIPTS_FOLDER_LOCATION/$STOP_SCRIPT_NAME"

########################################################################
# Kernel stuff - load modules that allow/support USB OTG host/gadget
########################################################################

# Function to check and append lines to a file if they don't exist
check_and_append_line() {
    local file_path="$1"
    local line_to_append="$2"
    
    # Check if the line already exists in the file
    if grep -qF "$line_to_append" "$file_path"; then
        warn "Line \"$line_to_append\" already in \"$file_path\"."
    else
        # Append the line only if it doesn't exist
        echo "$line_to_append" | sudo tee -a "$file_path"
        info "Line \"$line_to_append\" appended successfully to \"$file_path\"."
    fi
}

# Function to create backup file if the backup file doesn't already exist
create_backup() {
    local file_path="$1"
    local backup_file="${file_path}.backup"
    
    if [ ! -f "$backup_file" ]; then
        cp "$file_path" "$backup_file"
        info "Backup created for \"$file_path\" as \"$backup_file\"."
    else
        warn "Backup already exists for \"$file_path\". Skipping backup creation."
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
    warn "$USB_GADGET_FILE_LOCATION is missing. Loading the \"g_mass_storage\" kernel module.."
    modprobe g_mass_storage
fi

if [ ! -e "$USB_GADGET_FILE_LOCATION" ]; then
    echo -e "ERROR: $USB_GADGET_FILE_LOCATION is still missing. \nTry loading the kernel module manually using \"modprobe g_mass_storage\".\nCheck if loadead using \"lsmod | grep g_mass_storage\""
    exit 1
else
    info "Kernel module loaded successfully."
fi

########################################################################
# Create disk image to be used as a mass storage.
# Will not re-create the file if it already exists to protect data deletion.
########################################################################
if [ -e "$DISK_FILE_LOCATION" ]; then
    warn "Disk dile already exists and won't be recreated - \"$DISK_FILE_LOCATION\""
    warn "Get the data out and delete the file manually (rm $DISK_FILE_LOCATION) if you wish to re-create it."
else
    info "Creating a Disk image file at: \"$DISK_FILE_LOCATION\""
    
    # Disk size = block size * num blocks. /1024*1024 = 1MB/
    DISK_NUMBER_OF_BLOCKS=$(("$DISK_SIZE_IN_MB"*1024*1024/"$DISK_BLOCK_SIZE_IN_BYTES"))
    
    dd if=/dev/zero of="$DISK_FILE_LOCATION" bs="$DISK_BLOCK_SIZE_IN_BYTES" count="$DISK_NUMBER_OF_BLOCKS"

    # -S logical-sector-size
    # Specify the number of bytes per logical sector. Must be a power of 2 and greater than or equal to 512, i.e. 512, 1024, 2048, 4096, 8192, 16384, or 32768.
    mkdosfs "$DISK_FILE_LOCATION" -F 32 -I
    
    info "Disk file created. Size: $DISK_SIZE_IN_MB Mb. Block size: $DISK_BLOCK_SIZE_IN_BYTES bytes."
fi

########################################################################
# Create the SMB user if it's not the same as the rPI user (Raspberry Pi Imager)
########################################################################
user_found_count=$(grep -c "^$SMB_USERNAME:" /etc/passwd)

if [ $user_found_count -eq 0 ]; then
    info "The user $SMB_USERNAME does not exist and will be created"

    # Add a new user
    useradd -m $SMB_USERNAME

    # Set the password for the user
    echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | sudo passwd $SMB_USERNAME
else
    info "The user $SMB_USERNAME exists"
fi

########################################################################
# Get the UID and GID for the SMB user
########################################################################
# Use the id command to retrieve user information
user_info=$(id "$SMB_USERNAME")

# Extract UID and GID using awk
uid=$(echo "$user_info" | awk -F'=' '{print $2}' | awk -F'(' '{print $1}')
gid=$(echo "$user_info" | awk -F'=' '{print $3}' | awk -F'(' '{print $1}')

info "SMB User: $SMB_USERNAME , UID: $uid , GID: $gid"

########################################################################
# Create the script and populate it - it will run on every system boot
########################################################################
info "Populating the Start/Mount script"
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
if [ "\$EUID" -ne 0 ]; then
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
mkdir -p "$DISK_MNT_LOCATION"
mount -o loop,rw,uid=$uid,gid=$gid -t vfat "$DISK_FILE_LOCATION" "$DISK_MNT_LOCATION" # FOR IMAGE CREATED WITH DD
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
info "Populating the Stop/Unmount script"
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
if [ "\$EUID" -ne 0 ]; then
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

EOF

########################################################################
# Create a service to start the script
########################################################################
# Create the service file if it doesn't exist (first run)
SERVICE_FILE_LOCATION="/etc/systemd/system/$SERVICE_NAME"
if [ ! -e "$SERVICE_FILE_LOCATION" ]; then
    touch "$SERVICE_FILE_LOCATION"
fi

########################################################################
# Samba install 
########################################################################
    info "Installing Samba"
    apt update && apt install samba -y
    echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | sudo smbpasswd -a $SMB_USERNAME

    info "Configuring the SMB share"
    # Add Samba configuration
    bash -c "cat >> /etc/samba/smb.conf" <<EOL
    [usb]
    browseable = yes
    path = $DISK_MNT_LOCATION
    read only = no
    guest ok = yes
    create mask = 777
    valid users = $SMB_USERNAME
EOL

    info "Restarting the SMB service"
    # Restart Samba for the changes to take effect
    systemctl restart smbd.service


    info "Creating the service that will mount the USB thumb drive when powered on"
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

info "Enabling the service"
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
info "Service: \"$SERVICE_NAME\" created at \"$SERVICE_FILE_LOCATION\" and enabled/started."

########################################################################
# Reboot prompt
########################################################################
while true
do
    # warn "Confirm your disk setup looks correct before rebooting"
    # df -h
    
    read -r -p "Reboot now? [Y/n] " input

    case $input in
        [yY][eE][sS]|[yY])
    warn "Rebooting in 5 seconds"
    sleep 5
    reboot
    break
    ;;
        [nN][oO]|[nN])
    break
            ;;
        *)
    warn "Invalid input..."
    esac
done


