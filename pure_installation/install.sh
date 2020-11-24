#!/bin/bash

# setting timedate

timedate set-ntp true

#format partitions

echo 'Formating partitions'
yes | mkfs.ext4 /dev/sda1
yes | mkfs.ext4 /dev/sda3
yes | mkfs.ext4 /dev/sda4
mkswap /dev/sda2 ; swapon /dev/sda2

# mount partitions

echo 'Mounting root...'
mount /dev/sda3 /mnt
echo 'Mounting boot...'
mkdir /mnt/boot ; mount /dev/sda1 /mnt/boot
echo 'Mounting home...'
mkdir /mnt/home ; mount /dev/sda4 /mnt/home

# install base packages

pacstrap /mnt base base-devel linux linux-headers linux-firmware intel-ucode vim

# generate fstab

echo 'Generating fstab...'
genfstab -U /mnt >> /mnt/etc/fstab

# move script for root

cp backup/install-root.sh /mnt

# change root to /mnt

echo 'Changing root...'
arch-chroot /mnt
