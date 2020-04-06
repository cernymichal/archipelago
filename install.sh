#!/bin/sh
clear

# Assumptions
#   Root partition is mounted at $1
#   Root has /efi with mounted EFI partition

# Setup
NEW_ROOT=$1
NEW_KEYMAP=$2
NEW_ZONE=$3
NEW_HOSTNAME=$4
NEW_USER=$5
GRAPHICS_VENDOR=$(echo $6 | awk '{print tolower($0)}' )

# Download pacman config
echo "Downloading pacman configuration\n"
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/mirrorlist > /etc/pacman.d/mirrorlist
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/pacman.conf > /etc/pacman.conf

# Upgrade pacman to use multilib
pacman -Su

# Get microcode package
echo "\n\nDeciding what microcode and graphics drivers to use\n"
MICROCODE=$(
    CPU_VENDOR=$(cat /proc/cpuinfo | grep vendor | uniq | grep -oE '[^ ]+$')
    if [[ $CPU_VENDOR == "AuthenticAMD" ]]
    then
        echo "amd-ucode"
    elif [[ $CPU_VENDOR == "GenuineIntel" ]]
    then
        echo "intel-ucode"
    fi
)
echo "Microcode: $MICROCODE"

# Graphics
if [[ $GRAPHICS_VENDOR == "amd" ]]
then
    GRAPHICS_DRIVER=xf86-video-amdgpu
    OPENGL=mesa
    OPENGL32=lib32-mesa
elif [[ $GRAPHICS_VENDOR == "nvidia" ]]
then
    GRAPHICS_DRIVER=nvidia
    OPENGL=nvidia-utils
    OPENGL32=lib32-nvidia-utils
elif [[ $GRAPHICS_VENDOR == "intel" ]]
then
    GRAPHICS_DRIVER=nvidia
    OPENGL=nvidia-utils
    OPENGL32=lib32-nvidia-utils
fi
echo "Graphics: $GRAPHICS_DRIVER $OPENGL $OPENGL32"

# Set timedate ntp
timedatectl set-ntp true

# Pacstrap from arch repo
echo "\n\nInstalling base and other packages through pacstrap\n"
pacstrap $NEW_ROOT base base-devel linux linux-firmware $MICROCODE $GRAPHICS_DRIVER $OPENGL $OPENGL32 neovim go git grub efibootmgr python python-pip neofetch btrfs-progs grep xorg-xinit xorg lightdm redshift rofi pulseaudio firefox chromium ffmpeg youtube-dl pandoc feh vlc ranger discord steam

echo "\n\nDownloading locale\n"
# Download locale
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/locale.gen > $NEW_ROOT/etc/locale.gen

# Generate fstab and change root
echo "\n\nGenerating fstab\n"
genfstab -U $NEW_ROOT >> $NEW_ROOT/etc/fstab

# Create install script in for chroot
echo "\n\nCreating installation script in the new root\n"
cat <<EOF > $NEW_ROOT/install.sh
#!/bin/sh
# Change timezone
echo "\\n\\nChanging timezome\\n"
ln -sf /usr/share/zoneinfo/$NEW_ZONE /etc/localtime
hwclock --systohc

# Generate locale
echo "\\n\\nSetting up locale, language and keymap\\n"
locale-gen

# Set language and keymap
echo "LANG=$(cat /etc/locale.gen | head -n1 | awk '{print $1;}')" >> /etc/locale.conf
echo "KEYMAP=$NEW_KEYMAP" >> /etc/vconsole.conf

# Set hostname
echo "\\n\\nSetting hostname and generating hosts\\n"
echo $NEW_HOSTNAME >> /etc/hostname

# Generate hosts
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.0.1\t$NEW_HOSTNAME.localdomain $NEW_HOSTNAME" >> /etc/hosts

# Set root password and add a new user
echo"\\n\\nEnter a new password for root\\n"
until passwd
do
  echo "Try again"
done
echo"\\n\\nEnter a new password for your user\\n"
useradd -m -g wheel $NEW_USER
until passwd $NEW_USER
do
  echo "Try again"
done

# Setup bootloader
echo"\\n\\nSetting up grub\\n"
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install yay
echo"\\n\\nInstalling dmw, st, lemonbar and yay packages\\n"
git clone https://aur.archlinux.org/yay.git /usr/local/src/yay
chown -R $NEW_USER /usr/local/src/yay
$OLD_PWD=$(pwd)
cd /usr/local/src/yay
sudo -u $NEW_USER makepkg -si
cd $OLD_PWD

# Clone and make dwm, st and lemonbar
echo"\\n\\nInstalling dwm, st and lemon bar\\n"
git clone https://github.com/cernymichal/suckless /usr/local/src/suckless
make -C /usr/local/src/suckless/st clean install
make -C /usr/local/src/suckless/dwm clean install
chown -R $NEW_USER /usr/local/src/suckless

git clone https://github.com/LemonBoy/bar /usr/local/src/lemonbar
make -C /usr/local/src/lemonbar clean install
chown -R $NEW_USER /usr/local/src/lemonbar

# Install packages from the AUR
yay -Syu opentabletdriver-git yadm-git lightdm-mini-greeter joplin-desktop steam-fonts

# Clone dotfiles
echo"\\n\\nCloning dotfiles and linking them\\n"
sudo -u $NEW_USER yadm clone https://github.com/cernymichal/dotfiles

# Link mirrolist and locale.gen
ln -sf /home/$NEW_USER/.config/mirrorlist /etc/pacman.d/mirrorlist
ln -sf /home/$NEW_USER/.config/pacman.conf /etc/pacman.conf
ln -sf /home/$NEW_USER/.config/locale.gen /etc/locale.gen
EOF
chmod +x $NEW_ROOT/install.sh

# Chroot into the new istall and run the script above
echo "\n\nRunning install.sh chrooted\n"
arch-chroot $NEW_ROOT ./install.sh

# Remove the script
echo "\n\nRemoving install.sh\n"
rm $NEW_ROOT/install.sh