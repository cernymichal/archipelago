#!/bin/sh

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
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/mirrorlist > /etc/pacman.d/mirrorlist
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/pacman.conf > /etc/pacman.conf

# Upgrade pacman to use multilib
pacman -Syu

# Get microcode package
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

# Set timedate ntp
timedatectl set-ntp true

# Pacstrap from arch repo
pacstrap $NEW_ROOT base base-devel linux linux-firmware $MICROCODE $GRAPHICS_DRIVER $OPENGL $OPENGL32 neovim go git grub efibootmgr python python-pip neofetch btrfs-progs grep xorg-xinit xorg lightdm redshift rofi pulseaudio firefox chromium ffmpeg youtube-dl pandoc feh vlc ranger discord steam

# Download locale
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/locale.gen > $NEW_ROOT/etc/locale.gen

# Generate fstab and change root
genfstab -U $NEW_ROOT >> $NEW_ROOT/etc/fstab

# Create install script in for chroot
cat <<EOF > $NEW_ROOT/install.sh
#!/bin/sh
# Change timezone
ln -sf /usr/share/zoneinfo/$NEW_ZONE /etc/localtime
hwclock --systohc

# Generate locale
locale-gen

# Set language and keymap
echo "LANG=$(cat /etc/locale.gen | head -n1 | awk '{print $1;}')" >> /etc/locale.conf
echo "KEYMAP=$NEW_KEYMAP" >> /etc/vconsole.conf

# Set hostname
echo $NEW_HOSTNAME >> /etc/hostname

# Generate hosts
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.0.1\t$NEW_HOSTNAME.localdomain $NEW_HOSTNAME" >> /etc/hosts

# Set root password and add new user
passwd
useradd -m -g wheel $NEW_USER
passwd $NEW_USER

# Setup bootloader
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install yay
git clone https://aur.archlinux.org/yay.git /usr/local/src/yay
chown -r $NEW_USER /usr/local/src/yay
$OLD_PWD=$(pwd)
cd /usr/local/src/yay
sudo -u $NEW_USER makepkg -si
cd $OLD_PWD

# Clone and make dwm, st and lemonbar
git clone https://github.com/cernymichal/suckless /usr/local/src/suckless
make -C /usr/local/src/suckless/st clean install
make -C /usr/local/src/suckless/dwm clean install
chown -r $NEW_USER /usr/local/src/suckless

git clone https://github.com/LemonBoy/bar /usr/local/src/lemonbar
make -C /usr/local/src/lemonbar clean install
chown -r $NEW_USER /usr/local/src/lemonbar

# Install packages from the AUR
yay -Syu opentabletdriver-git yadm-git lightdm-mini-greeter joplin-desktop steam-fonts

# Clone dotfiles
sudo -u $NEW_USER yadm clone https://github.com/cernymichal/dotfiles

# Link mirrolist and locale.gen
ln -sf /home/$NEW_USER/.config/mirrorlist /etc/pacman.d/mirrorlist
ln -sf /home/$NEW_USER/.config/pacman.conf /etc/pacman.conf
ln -sf /home/$NEW_USER/.config/locale.gen /etc/locale.gen
EOF

# Chroot into the new istall and run the script above
arch-chroot $NEW_ROOT $NEW_ROOT/install.sh

# Remove the script
rm $NEW_ROOT/install.sh