#!/bin/bash
# Complete Arch Linux Gaming Setup Installer
# Downloads everything from internet - use with official Arch ISO

set -e

echo "=== Arch Linux Gaming Setup Installer ==="
echo "User: veloxsz (password: 8991)"
echo "Includes: KDE, Docker, Java 17, Maven, Steam, Gaming, Development tools"
echo ""

# Set keyboard layout
loadkeys br-abnt2

# Ensure we have internet
echo "Testing internet connection..."
if ! ping -c 1 google.com &> /dev/null; then
    echo "No internet connection. Please connect to internet first."
    echo "Use: iwctl (for WiFi) or check ethernet connection"
    exit 1
fi

# Update system clock
timedatectl set-ntp true

# Show available disks
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop

echo ""
read -p "Enter the disk to install to (e.g., sda, nvme0n1, vda): " DISK

# Validate disk exists
if [[ ! -b "/dev/$DISK" ]]; then
    echo "Error: /dev/$DISK does not exist!"
    exit 1
fi

echo ""
echo "WARNING: This will COMPLETELY ERASE /dev/$DISK"
read -p "Are you sure? Type 'yes' to continue: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Installation cancelled."
    exit 1
fi

echo ""
echo "Starting installation on /dev/$DISK..."

# Partition the disk
echo "Partitioning disk..."
parted /dev/$DISK --script mklabel msdos
parted /dev/$DISK --script mkpart primary ext4 1MiB 100%
parted /dev/$DISK --script set 1 boot on

# Wait for partitions to be recognized
sleep 2

# Determine partition name
if [[ $DISK =~ ^nvme ]]; then
    PART="/dev/${DISK}p1"
else
    PART="/dev/${DISK}1"
fi

# Format partition
echo "Formatting partition $PART..."
mkfs.ext4 -F $PART

# Mount partition
echo "Mounting partition..."
mount $PART /mnt

# Enable multilib before installation
echo "Configuring package repositories..."
sed -i '/\[multilib\]/,/Include.*mirrorlist/ s/^#//' /etc/pacman.conf
pacman -Sy

# Install base system
echo "Installing base system..."
pacstrap /mnt base base-devel linux linux-firmware grub networkmanager sudo

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configure the system
echo "Configuring system..."
arch-chroot /mnt /bin/bash << EOF
# Set timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

# Set locale
echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf

# Set keyboard layout
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# Set hostname
echo "arch-gaming" > /etc/hostname
cat << 'HOSTS' > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch-gaming.localdomain arch-gaming
HOSTS

# Set root password
echo "root:8991" | chpasswd

# Create user account
useradd -m -G wheel -s /bin/bash veloxsz
echo "veloxsz:8991" | chpasswd

# Configure sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable multilib in installed system
sed -i '/\[multilib\]/,/Include.*mirrorlist/ s/^#//' /etc/pacman.conf
pacman -Sy

# Install and configure GRUB
grub-install /dev/$DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

echo "Base system configured. Installing packages..."

# Install all packages
pacman -S --noconfirm --needed \
    pipewire pipewire-pulse pipewire-alsa pipewire-jack \
    plasma-meta lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings \
    konsole dolphin kate spectacle gwenview okular ark kcalc \
    ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji \
    mesa lib32-mesa vulkan-intel lib32-vulkan-intel vulkan-radeon lib32-vulkan-radeon \
    xf86-video-intel nvidia nvidia-utils lib32-nvidia-utils xf86-video-amdgpu \
    git docker docker-compose jdk17-openjdk maven nodejs npm \
    python python-pip vim nano wget curl unzip zip zsh \
    steam wine winetricks lutris \
    htop neofetch tree lsof strace man-db man-pages \
    unrar p7zip gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav \
    binutils make gcc fakeroot debugedit openssh xdg-utils

# Enable services
systemctl enable lightdm
systemctl enable docker

# Add user to docker group
usermod -aG docker veloxsz

# Configure LightDM
cat << 'LIGHTDM_CONF' > /etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
background = #2c3e50
theme-name = Breeze-Dark
icon-theme-name = breeze-dark
font-name = Noto Sans 11
cursor-theme-name = breeze_cursors
show-clock = true
clock-format = %H:%M
LIGHTDM_CONF

# Create complete setup script for AUR packages
cat << 'COMPLETE_SETUP' > /home/veloxsz/complete-setup.sh
#!/bin/bash
echo "=== Post-Installation Setup ==="
echo "Installing AUR helper and packages..."

# Install yay
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd /home/veloxsz

echo "Installing AUR packages..."
yay -S --noconfirm \
    brave-bin \
    visual-studio-code-bin \
    heroic-games-launcher-bin \
    nvm

echo "Setting up NVM..."
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"

# Install and setup Powerlevel10k
echo "Setting up Powerlevel10k..."
yay -S --noconfirm zsh-theme-powerlevel10k-git

# Install zsh and oh-my-zsh for better experience
sudo pacman -S --noconfirm zsh
sh -c "\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Setup Powerlevel10k in .zshrc
echo 'source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme' >> ~/.zshrc

# Change default shell to zsh
chsh -s /bin/zsh

# Check if user has a p10k config, if not create a placeholder
if [ ! -f ~/.p10k.zsh ]; then
    echo "Downloading Powerlevel10k configuration from GitHub..."
    if curl -fsSL https://raw.githubusercontent.com/gianmnf/arch-install/main/.p10k.zsh -o ~/.p10k.zsh; then
        echo "✓ Successfully downloaded .p10k.zsh config"
    else
        echo "⚠ Could not download .p10k.zsh from GitHub, creating placeholder"
        echo "# Powerlevel10k configuration placeholder" > ~/.p10k.zsh
        echo "# Replace this file with your own .p10k.zsh config" >> ~/.p10k.zsh
        echo "# Run 'p10k configure' to create a new config" >> ~/.p10k.zsh
    fi
fi

# Source p10k config in .zshrc
echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> ~/.zshrc

# Add NVM to zshrc (not bashrc since we're using zsh now)
cat << 'NVM_ZSHRC' >> ~/.zshrc

# NVM setup
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
NVM_ZSHRC

# Source zshrc and install Node
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
nvm alias default lts/*

# Set up KDE shortcuts and default applications
echo "Configuring KDE shortcuts and default browser..."

# Create KDE config directories
mkdir -p ~/.config
mkdir -p ~/.local/share/applications

# Set Brave as default browser
xdg-settings set default-web-browser brave-browser.desktop

# Create custom shortcut for Ctrl+Alt+T (terminal)
# This will be applied when KDE starts
mkdir -p ~/.config/khotkeysrc.d

cat << 'SHORTCUT_CONFIG' > ~/.config/kglobalshortcutsrc
[konsole.desktop]
NewTab=none,none,Open a New Tab
NewWindow=Ctrl+Alt+T,none,Open a New Window
_k_friendly_name=Konsole

[kwin]
ShowDesktopGrid=Ctrl+F8,Ctrl+F8,Show Desktop Grid
SHORTCUT_CONFIG

echo ""
echo "=== Setup Complete! ==="
echo "Installed:"
echo "✓ KDE Plasma Desktop"
echo "✓ Docker + Docker Compose"
echo "✓ Java 17 + Maven"
echo "✓ Node.js (via NVM) + NPM"
echo "✓ Steam + Wine + Lutris"
echo "✓ Brave Browser (set as default)"
echo "✓ Visual Studio Code"
echo "✓ Heroic Games Launcher"
echo "✓ Zsh + Oh My Zsh + Powerlevel10k"
echo "✓ Powerlevel10k config downloaded from GitHub"
echo "✓ Development tools (git, vim, etc.)"
echo "✓ Terminal shortcut: Ctrl+Alt+T"
echo ""
echo "IMPORTANT:"
echo "1. Log out and log back in for all changes to take effect"
echo "2. Your default shell is now zsh with your custom Powerlevel10k theme"
echo "3. If the GitHub download failed, run 'p10k configure' to create a new config"
COMPLETE_SETUP

chown veloxsz:veloxsz /home/veloxsz/complete-setup.sh
chmod +x /home/veloxsz/complete-setup.sh

# Create a welcome message
cat << 'WELCOME' > /home/veloxsz/README.txt
=== Welcome to your Arch Gaming Setup ===

Your system is ready! Here's what's installed:

DESKTOP ENVIRONMENT:
- KDE Plasma with LightDM login manager
- Brazilian keyboard layout configured

DEVELOPMENT TOOLS:
- Git, Docker, Docker Compose
- Java 17 (OpenJDK) + Maven
- Node.js + NPM (via NVM)
- Python + pip
- Visual Studio Code

GAMING:
- Steam (with 32-bit libraries)
- Wine + Winetricks
- Lutris game manager
- Heroic Games Launcher

BROWSER:
- Brave Browser (set as default)

SHELL & TERMINAL:
- Zsh with Oh My Zsh
- Powerlevel10k theme (auto-downloaded from GitHub)
- Terminal shortcut: Ctrl+Alt+T

NEXT STEPS:
1. The system will reboot automatically
2. Login with: veloxsz / 8991
3. Run: ./complete-setup.sh (installs AUR packages + downloads your .p10k.zsh)
4. Change your password: passwd
5. Enjoy your system!

CREDENTIALS:
- User: veloxsz
- Password: 8991
- Root password: 8991

Remember to change these passwords after first login!
WELCOME

chown veloxsz:veloxsz /home/veloxsz/README.txt

EOF

# Unmount and finish
umount -R /mnt

echo ""
echo "=== INSTALLATION COMPLETE! ==="
echo ""
echo "System installed successfully on /dev/$DISK"
echo ""
echo "Login credentials:"
echo "  User: veloxsz"
echo "  Password: 8991"
echo ""
echo "After first login:"
echo "1. Run: ./complete-setup.sh"
echo "2. Read: README.txt"
echo "3. Change your passwords!"
echo ""
echo "Rebooting in 10 seconds..."
sleep 10
systemctl reboot
