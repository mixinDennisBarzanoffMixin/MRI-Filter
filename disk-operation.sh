#!/bin/bash

DIR="/home/rumen/Desktop/MRI"
sleep 5
cd_device=$(lsblk -no NAME,TYPE | grep 'rom' | awk '{print $1}')

cleanup() {
    # Check if the disc is mounted
    if grep -qs '/media/disc' /proc/mounts; then
        echo "Removing mounted disc from /media/disc"
        pkexec umount /media/disc || error_exit "Failed to unmount disc"
    fi

    echo "Removing $DIR/images/*, $DIR/denoised/*, and $DIR/CD-DATA/*"
    pkexec rm -rf "$DIR/images/*" "$DIR/denoised/*" "$DIR/CD-DATA/*"

    # Attempt to eject the disc only if it's present
    if [ -b /dev/$cd_device ]; then
        eject /dev/$cd_device || error_exit "Failed to eject disc"
    fi
}



function error_exit {
    zenity --error --width=300 --text="$1"
    exit 1
}

# Trap the cleanup function on signals: exit, SIGINT, SIGTERM
trap cleanup EXIT SIGINT SIGTERM

# Display basic text
zenity --info --width=300 --text="Starting the automation process..."

# Mount the inserted disc to a location
mkdir -p /media/disc
pkexec mount -o uid=$(id -u),gid=$(id -g),dmask=022,fmask=133 /dev/sr0 /media/disc || error_exit "Failed to mount the disc."


echo "Removing $DIR/images/* and $DIR/denoised/*"
rm -rf "$DIR/denoised/*" || error_exit "Failed to remove denoised files."
rm -rf "$DIR/images/*" || error_exit "Failed to remove images."
rm -rf "$DIR/CD-DATA/*" || error_exit "Failed to remove CD-DATA."

echo "Moving data to the MRI directory on Desktop"
whoami
# Copy data from the disc to ~/Desktop/MRI
cp --no-preserve=mode -R /media/disc/* "$DIR/images" || error_exit "Failed to copy data from the disc to MRI directory."
#chmod u+rw "$DIR/images/*" || error_exit "Failed to change permissions of images/ directory"

# Unmount the disc
pkexec umount /media/disc || error_exit "Failed to unmount the disc."
eject /dev/$cd_device || error_exit "Failed to eject disc"

echo "Changing directory"
cd $DIR || error_exit "Failed to change directory."

echo "Activating python environment for filter"
source mri-env/bin/activate || error_exit "Failed to activate the python environment."

pip3 install -r requirements.txt

# Run your script over the data
python3 denoise.py images/ || error_exit "Failed to run denoise.py."

cp -R denoised/* CD-DATA/ || error_exit "Failed to copy denoised data to CD-DATA."

# Copy additional files
cp -R VIEWER2/* CD-DATA/ || error_exit "Failed to copy VIEWER2 files to CD-DATA."

while true; do
    zenity --question --width=300 --text="Please insert a new writable disc and press OK."
    decision=$?

    # If OK was pressed
    if [ $decision -eq 0 ]; then
        # Check if the inserted disc is writable. This is a simple check; you might want to elaborate further.
        if [ -w /dev/sr0 ]; then
            break
        else
            zenity --error --width=300 --text="Inserted disc is not writable. Please try another."
        fi
    # If Cancel was pressed or Zenity dialog was closed
    elif [ $decision -eq 1 ]; then
        if zenity --question --width=300 --text="Do you want to exit the process?"; then
            error_exit "User terminated the process."
        fi
    # If Zenity timed out (if you have a timeout option set)
    elif [ $decision -eq 5 ]; then
        if zenity --question --width=300 --text="Dialog timed out. Do you want to exit the process?"; then
            error_exit "User terminated the process."
        fi
    fi
done



# Create an ISO from the ~/Desktop/MRI/CD-DATA directory
mkisofs -o /tmp/new_disc.iso "$DIR/CD-DATA/" || error_exit "Failed to create an ISO."


# Burn the ISO to the new disc
cdrecord -v dev=/dev/sr0 /tmp/new_disc.iso || error_exit "Failed to burn the ISO to the new disc."
pkexec chown rumen:rumen /tmp/new_disc.iso
chmod 644 /tmp/new_disc.iso

# Notify completion
zenity --info --width=300 --text="Process completed."

# Clean up the temporary ISO
rm /tmp/new_disc.iso || error_exit "Failed to remove the temporary ISO."

