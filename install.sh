# Setup
NEW_KEYMAP=$1
NEW_ZONE=$2
NEW_HOSTNAME=$3
NEW_USER=$4
GRAPHICS_VENDOR=$(echo $5 | awk '{print tolower($0)}' )

# Download locale and mirrorlist
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/mirrorlist > /etc/pacman.d/mirrorlist
curl -LJ https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/locale.gen > /mnt/etc/locale.gen

# Select first language from what/locale.gen
NEW_LANG=$(cat /mnt/etc/locale.gen | head -n1 | awk '{print $1;}') 

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

# Pacstrap base + other bins from arch repo
pacstrap /mnt base base-devel linux linux-firmware $MICROCODE $GRAPHICS_DRIVER $OPENGL $OPENGL32 neovim go git grub efibootmgr python python-pip neofetch btrfs-progs grep xorg-xinit xorg lightdm lightdm-mini-greeter redshift rofi pulseaudio firefox chromium ffmpeg youtube-dl pandoc feh vlc ranger joplin-desktop discord steam steam-fonts

# Generate fstab and change root
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt

# Change timezone
ln -sf /usr/share/zoneinfo/$NEW_ZONE /etc/localtime
hwclock --systohc

# Generate locale
locale-gen

# Set language and keymap
echo "LANG=$NEW_LANG" >> /etc/locale.conf
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

# Install opentabletdriver
yay -Syu opentabletdriver-git

# Install yadm (dotfile managment)
yay -S yadm-git

# Clone dotfiles
sudo -u $NEW_USER yadm clone https://github.com/cernymichal/dotfiles

# Link mirrolist and locale.gen
ln -sf /home/$NEW_USER/.config/mirrorlist /etc/pacman.d/mirrorlist
ln -sf /home/$NEW_USER/.config/locale.gen /etc/locale.gen

# Exit from chroot
exit