#!/bin/bash

DIR="/home/rumen/Desktop/MRI"
sleep 5
cd_device=$(lsblk -no NAME,TYPE | grep 'rom' | awk '{print $1}')

cleanup() {
    # Check if the disc is mounted
    if grep -qs '/media/disc' /proc/mounts; then
        echo "Премахване на монтирания диск от /media/disc"
        pkexec umount /media/disc || error_exit "Неуспешно демонтиране на диска."
    fi

    echo "Премахване на $DIR/images/*, $DIR/denoised/*, и $DIR/CD-DATA/*"
    pkexec rm -rf "$DIR/images/*" 
    pkexec rm -rf "$DIR/denoised/*"
    pkexec rm -rf "$DIR/CD-DATA/*"

    # Attempt to eject the disc only if it's present
    if [ -b /dev/$cd_device ]; then
        eject /dev/$cd_device || error_exit "Неуспешно изваждане на диска."
    fi
}

error_exit() {
    zenity --error --width=300 --text="$1"
    exit 1
}

trap cleanup EXIT SIGINT SIGTERM

zenity --info --width=300 --text="Започване на автоматизирания процес..."

mkdir -p /media/disc
pkexec mount -o uid=$(id -u),gid=$(id -g),dmask=022,fmask=133 /dev/sr0 /media/disc || error_exit "Неуспешно монтиране на диска."

echo "Премахване на $DIR/images/* и $DIR/denoised/*"
pkexec rm -rf "$DIR/denoised/*" || error_exit "Неуспешно премахване на дешумените файлове."
pkexec rm -rf "$DIR/images/*" || error_exit "Неуспешно премахване на изображенията."
pkexec rm -rf "$DIR/CD-DATA/*" || error_exit "Неуспешно премахване на изображенията."

echo "Преместване на данни към MRI директорията на работния плот"
cp --no-preserve=mode -R /media/disc/* "$DIR/images" || error_exit "Неуспешно копиране на данни от диска към MRI директория."

pkexec umount /media/disc || error_exit "Неуспешно демонтиране на диска."
eject /dev/$cd_device || error_exit "Неуспешно изваждане на диска."

cd $DIR || error_exit "Неуспешно променяне на директорията."

source mri-env/bin/activate || error_exit "Неуспешно активиране на python средата."

pip3 install -r requirements.txt

python3 denoise.py images/ || error_exit "Грешка при стартиране на denoise.py."

cp -R denoised/* CD-DATA/ || error_exit "Неуспешно копиране на дешумените данни към CD-DATA."

while true; do
    zenity --question --width=300 --text="Моля, поставете нов записващ диск и натиснете OK."
    decision=$?

    if [ $decision -eq 0 ]; then
        if [ -w /dev/sr0 ]; then
            break
        else
            zenity --error --width=300 --text="Поставеният диск не може да бъде записан. Моля, опитайте с друг."
        fi
    elif [ $decision -eq 1 ]; then
        if zenity --question --width=300 --text="Искате ли да прекратите процеса?"; then
            error_exit "Потребителят прекрати процеса."
        fi
    elif [ $decision -eq 5 ]; then
        if zenity --question --width=300 --text="Диалоговият прозорец изтече. Искате ли да прекратите процеса?"; then
            error_exit "Потребителят прекрати процеса."
        fi
    fi
done


mkisofs -o -J -R -l -V "MBALLOM" /tmp/new_disc.iso "$DIR/CD-DATA/" || error_exit "Неуспешно създаване на ISO."

sleep 3

cdrecord -v dev=/dev/sr0 /tmp/new_disc.iso || error_exit "Грешка при записване на ISO на новия диск."

pkexec chown rumen:rumen /tmp/new_disc.iso
chmod 644 /tmp/new_disc.iso

zenity --info --width=300 --text="Процесът завърши успешно."

rm /tmp/new_disc.iso || error_exit "Грешка при премахване на временния ISO."
