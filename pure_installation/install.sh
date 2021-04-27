#!/bin/sh
echo -e "Hi. This is prototype script for seting up arch linux without DE.\n"
echo -n "To continue with installation press [Enter] or type [q] to exit > "; read enter

if [[ $enter = 'q' ]]; then echo "exiting..."; exit; fi

# setting timedate

echo -e "\n* setting time and date with \`timedate set-ntp true\`"
# timedate set-ntp true

#format partitions

echo -e "Format partitions\n"

# echo 'Formating partitions'
# yes | mkfs.ext4 /dev/sda1
# yes | mkfs.ext4 /dev/sda3
# yes | mkfs.ext4 /dev/sda4
# mkswap /dev/sda2 ; swapon /dev/sda2

# # mount partitions

# echo 'Mounting root...'
# mount /dev/sda3 /mnt
# echo 'Mounting boot...'
# mkdir /mnt/boot ; mount /dev/sda1 /mnt/boot
# echo 'Mounting home...'
# mkdir /mnt/home ; mount /dev/sda4 /mnt/home

# # configure mirrorlist
# vim /etc/pacman.d/mirrorlist

# # install base packages

# pacstrap /mnt base base-devel linux linux-headers linux-firmware intel-ucode vim

# # generate fstab

# echo 'Generating fstab...'
# genfstab -U /mnt >> /mnt/etc/fstab

# # move script for root

# cp backup/install-root.sh /mnt

# # change root to /mnt

# echo 'Changing root...'
# arch-chroot /mnt
