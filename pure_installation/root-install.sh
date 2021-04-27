#!/bin/bash

# set time zone

echo 'Setting time-zone...'
ln -sf /usr/share/zoneinfo/Europe/Sarajevo /etc/localtime
hwclock --systohc

# install locale

sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
sed -i '/bs_BA.UTF-8/s/^#//g' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

# configure host

echo 'Editing hosts...'
echo arch > /etc/hostname
printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\tarch.localdomain\tarch" >> /etc/hosts

# generate initframs

mkinitcpio -P

# enter root passwd

echo 'Enter new root password'
passwd

# install other packages

yes | pacman -S reflector
reflector --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
yes | pacman -S grub networkmanager bluez bluez-utils pulseaudio-bluetooth xdg-user-dirs

# install grub

grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# enable services & reflector

echo -e '--save /etc/pacman.d/mirrorlist\n--latest 5\n--sort rate' > /etc/xdg/reflector/reflector.conf

echo 'Enabling services...'
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable reflector

# add new user with password

echo 'Enter new username'
read -p 'Username: ' USER
useradd -mG wheel $USER
echo 'Enter password for new user'
passwd $USER

# uncomment wheel group

echo 'Editing sudoers...'
sed -i '/%wheel ALL=(ALL) NOPASSWD: ALL/s/^#//g' /etc/sudoers
