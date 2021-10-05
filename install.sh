#!/bin/sh
clear

# Assumptions
#   Root partition is mounted at $1
#   Root has /efi with mounted EFI partition

# Setup
NEW_ROOT="$1"
NEW_KEYMAP="$2"
NEW_X11_KEYMAP="$3"
NEW_ZONE="$4"
NEW_HOSTNAME="$5"
NEW_USER="$6"
GRAPHICS_VENDOR=$(echo "$7" | tr '[:upper:]' '[:lower:]')

NEW_USER_PASSWORD=""
NEW_ROOT_PASSWORD=""

read_secret () {
    stty -echo
    trap 'stty echo' EXIT
    read "$@"
    stty echo
    trap - EXIT
    echo
}

read_password () {
    local password=""
    local password2=""
    while true
    do
        printf "Password: "
        read_secret password
        printf "Repeat password: "
        read_secret password2

        if [ "$password" = "$password2" ]
        then
            eval "$@='$password'"
            return
        else
            echo "Passwords don't match"
        fi
    done
}

# Get passwords
echo -e "\n>Enter a new password for your user\n"
read_password NEW_USER_PASSWORD
echo -e "\n>Enter a new password for root\n"
read_password NEW_ROOT_PASSWORD

# Download pacman config
echo -e "Downloading pacman configuration\n"
curl -L https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/mirrorlist > /etc/pacman.d/mirrorlist
curl -L https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/pacman.conf > /etc/pacman.conf

# Get microcode package
echo -e "\n>Deciding what microcode and graphics drivers to use\n"
MICROCODE=$(
    CPU_VENDOR=$(cat /proc/cpuinfo | grep vendor | uniq | grep -oE '[^ ]+$')
    if [ "$CPU_VENDOR" = "AuthenticAMD" ]
    then
        echo "amd-ucode"
    elif [ "$CPU_VENDOR" = "GenuineIntel" ]
    then
        echo "intel-ucode"
    fi
)
echo "Microcode: $MICROCODE"

# Graphics
if [ "$GRAPHICS_VENDOR" = "amd" ]
then
    GRAPHICS_DRIVER=xf86-video-amdgpu
    OPENGL=mesa
    OPENGL32=lib32-mesa
elif [ "$GRAPHICS_VENDOR" = "nvidia" ]
then
    GRAPHICS_DRIVER=nvidia
    OPENGL=nvidia-utils
    OPENGL32=lib32-nvidia-utils
elif [ "$GRAPHICS_VENDOR" = "intel" ]
then
    GRAPHICS_DRIVER=nvidia
    OPENGL=nvidia-utils
    OPENGL32=lib32-nvidia-utils
fi
echo "Graphics: $GRAPHICS_DRIVER $OPENGL $OPENGL32"

# Set timedate ntp
timedatectl set-ntp true

# Pacstrap from arch repo
echo -e "\n>Installing base and other packages through pacstrap\n"
pacstrap $NEW_ROOT base base-devel linux linux-firmware xf86-input-libinput $MICROCODE $GRAPHICS_DRIVER $OPENGL $OPENGL32 neovim nano htop networkmanager go git grub efibootmgr python python-pip neofetch btrfs-progs xorg-xinit xorg gnome gnome-tweak-tool drawing

# Download locale and sudoers
echo -e "\n>Downloading locale\n"
curl -L https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/locale.gen > $NEW_ROOT/etc/locale.gen
curl -L https://raw.githubusercontent.com/cernymichal/dotfiles/master/.config/sudoers > $NEW_ROOT/etc/sudoers

# Generate fstab and change root
echo -e "\n>Generating fstab\n"
genfstab -U $NEW_ROOT >> $NEW_ROOT/etc/fstab

# Create install script in for chroot
echo -e "\n>Creating installation script in the new root\n"
cat <<EOF > $NEW_ROOT/install.sh
#!/bin/sh
# Change timezone
echo -e "\\n>Changing timezome\\n"
ln -sf /usr/share/zoneinfo/$NEW_ZONE /etc/localtime
hwclock --systohc

# Generate locale
echo -e "\\n>Setting up locale, language and keymap\\n"
locale-gen

# Set language and keymap
echo "LANG=$(cat /etc/locale.gen | head -n1 | awk '{print $1;}')" > /etc/locale.conf
echo "KEYMAP=$NEW_KEYMAP" > /etc/vconsole.conf
localectl --no-convert set-x11-keymap $NEW_X11_KEYMAP

# Set hostname
echo -e "\\n>Setting hostname and generating hosts\\n"
echo $NEW_HOSTNAME > /etc/hostname

# Generate hosts
echo -e "127.0.0.1\\tlocalhost\\n::1\\t\\tlocalhost\\n127.0.0.1\\t$NEW_HOSTNAME.localdomain\\t$NEW_HOSTNAME" > /etc/hosts

# Set root password and add a new user
echo -e "$NEW_ROOT_PASSWORD\\n$NEW_ROOT_PASSWORD" | passwd
useradd -m -g wheel $NEW_USER
echo -e "$NEW_USER_PASSWORD\\n$NEW_USER_PASSWORD" | passwd $NEW_USER

# Setup bootloader
echo -e "\\n>Setting up grub\\n"
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install yay
echo -e "\\n>Installing yay\\n"
git clone https://aur.archlinux.org/yay.git /usr/local/src/yay
chown -R $NEW_USER /usr/local/src/yay
cd /usr/local/src/yay
sudo -u $NEW_USER makepkg -si

# Install packages from the AUR
echo -e "\\n>Installing packages from the AUR\\n"
yay -Syu yadm

# Clone dotfiles
echo -e "\\n>Cloning dotfiles and linking them\\n"
rm /home/$NEW_USER/.bashrc
rm -rf /home/$NEW_USER/.config
sudo -u $NEW_USER yadm clone --bootstrap -b master https://github.com/cernymichal/dotfiles

# Link mirrorlist, pacman.conf, locale.gen and bashrc and copy sudoers
sudo -u $NEW_USER /home/$NEW_USER/.local/bin/linkdots.sh

# Enable services
systemctl enable NetworkManager
systemctl enable gdm.service
EOF
chmod +x $NEW_ROOT/install.sh

# Chroot into the new istall and run the script above
echo -e "\n>Running install.sh chrooted\n"
arch-chroot $NEW_ROOT /install.sh
rm $NEW_ROOT/install.sh
