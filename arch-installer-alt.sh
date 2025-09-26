#!/bin/bash

# Getting user inputs
while getopts "u:p:rp:a:gp" opt; do
  case $opt in
    u)
      username=$OPTARG
      ;;
    p)
      password=$OPTARG
      ;;
    rp)
      root_password=$OPTARG
      ;;
    a)
      architecture=$OPTARG
      ;;
    gp)
      gpu=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

echo ""
echo "-------------------------------------"
echo "| AUTOMATED ARCH INSTALL BY VELOXSZ |"
echo "-------------------------------------"
echo ""

echo ""
echo "-------------------------------------"
echo "|       1 - KEYBOARD LAYOUT         |"
echo "-------------------------------------"
echo ""
# If you already know your keyboard layout add it through this variable:
KBD_LAYOUT=br-abnt2 # This would load the brazilian abnt2 layout

if [[ -n "$KBD_LAYOUT" ]]; then
    loadkeys "$KBD_LAYOUT"
    echo "Keyboard layout '$KBD_LAYOUT' applied successfully."
else
  echo "Scanning for available keyboard layouts..."
  map_files=($(ls /usr/share/kbd/keymaps/**/*.map.gz))
  declare -a map_names
  index=0
  for file in "${map_files[@]}"; do
      # Extract the base name (e.g., us, br-abnt2) and remove the .map.gz extension.
      # The `|&` is a non-standard bash feature to redirect stderr to stdout, 
      # but the `basename` and `sed` combo is more robust here.
      base_name=$(basename "$file" .map.gz)
      map_names[$index]="$base_name"
      index=$((index + 1))
  done

  echo ""
  echo "Please select a keyboard layout by typing its number:"
  for i in "${!map_names[@]}"; do
      printf "%3d) %s\n" "$((i + 1))" "${map_names[i]}"
  done
  echo ""

  while true; do
    read -p "Enter number: " choice

    # Check if the input is a valid number and within the range of the list.
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#map_names[@]} )); then
        # Valid input.
        selected_index=$((choice - 1))
        KBD_LAYOUT="${map_names[selected_index]}"
        break
    else
        # Invalid input.
        echo "Invalid selection. Please enter a number between 1 and ${#map_names[@]}."
    fi
  done

  loadkeys "$KBD_LAYOUT"
  echo "Keyboard layout '$KBD_LAYOUT' applied successfully."
fi

echo ""
echo "-------------------------------------"
echo "|           2 - TIMEZONES           |"
echo "-------------------------------------"
echo ""
# If you already know your timezone add it through this variable:
# TZ= America/Sao_Paulo

if [[ -n "$TZ" ]]; then
    timedatectl set-timezone "$TZ"
    echo "Timezone '$TZ' applied successfully."
else
  echo "Scanning for available keyboard layouts..."
  region_files=($(ls /usr/share/zoneinfo/))
  declare -a regions
  for file in "${region_files[@]}"; do
      if [[ "$file" != "posix" && "$file" != "right" && "$file" != "localtime" && "$file" != "zone.tab" && "$file" != "UTC" && -d "/usr/share/zoneinfo/$file" ]]; then
        regions+=("$file")
      fi
  done

  echo ""
  echo "Please select a timezone region by typing its number:"
  for i in "${!regions[@]}"; do
      printf "%3d) %s\n" "$((i + 1))" "${regions[i]}"
  done
  echo ""

  while true; do
    read -p "Enter region number: " region_choice

    if [[ "$region_choice" =~ ^[0-9]+$ ]] && (( region_choice > 0 && region_choice <= ${#regions[@]} )); then
        selected_region="${regions[$((region_choice - 1))]}"
        break
    else
        echo "Invalid selection. Please enter a number between 1 and ${#regions[@]}."
    fi
  done

  echo ""
  echo "Scanning for timezones within '$selected_region'..."
  timezone_files=($(ls "/usr/share/zoneinfo/$selected_region"))
  declare -a timezones

  for file in "${timezone_files[@]}"; do
      if [[ -f "/usr/share/zoneinfo/$selected_region/$file" ]]; then
          timezones+=("$file")
      fi
  done

  IFS=$'\n' sorted_timezones=($(sort <<<"${timezones[*]}"))
  unset IFS

  echo ""
  echo "Please select a timezone from '$selected_region' by typing its number:"
  for i in "${!sorted_timezones[@]}"; do
      printf "%3d) %s\n" "$((i + 1))" "${sorted_timezones[i]}"
  done
  echo ""

  while true; do
    read -p "Enter timezone number: " timezone_choice

    if [[ "$timezone_choice" =~ ^[0-9]+$ ]] && (( timezone_choice > 0 && timezone_choice <= ${#sorted_timezones[@]} )); then
        selected_timezone="${sorted_timezones[$((timezone_choice - 1))]}"
        TZ="$selected_region/$selected_timezone"
        break
    else
        echo "Invalid selection. Please enter a number between 1 and ${#sorted_timezones[@]}."
    fi
  done

  timedatectl set-timezone "$TZ"
  echo "Timezone '$TZ' applied successfully."

fi

echo ""
echo "------------------------------------"
echo "|       3 - DISK FORMATTING        |"
echo "------------------------------------"
echo ""
lsblk -d -o NAME,SIZE,MODEL | grep -v loop

AVAILABLE_DISKS=($(lsblk -d -n -o NAME | grep -v loop))
if [ ${#AVAILABLE_DISKS[@]} -eq 1 ]; then
    DISK=${AVAILABLE_DISKS[0]}
    echo ""
    echo "Only one disk found: $DISK"
    read -p "Use /dev/$DISK for installation? [Y/n]: " AUTO_CONFIRM < /dev/tty
    if [[ $AUTO_CONFIRM =~ ^[Nn] ]]; then
        read -p "Enter the disk to install to (e.g., sda, nvme0n1, vda): " DISK < /dev/tty
    fi
else
    echo ""
    read -p "Enter the disk to install to (e.g., sda, nvme0n1, vda): " DISK < /dev/tty
fi

if [[ ! -b "/dev/$DISK" ]]; then
    echo "Error: /dev/$DISK does not exist!"
    exit 1
fi

echo ""
echo "This script will create a root (/) and a swap partition."
echo "You can either use an existing EFI partition (for dual-booting) or create a new one."
read -p "Do you have an existing EFI partition? (yes/no): " HAS_EFI

echo "Creating a new GPT partition table on /dev/$DISK. This will ERASE ALL DATA."
read -p "Are you sure? Type 'yes' to continue: " CONFIRM < /dev/tty

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Installation cancelled."
    exit 1
fi
parted -s "/dev/$DISK" mklabel gpt

EFI_SIZE="1024MiB"
SWAP_SIZE="8GiB"

if [[ "$HAS_EFI" == "yes" ]]; then
    read -p "Enter the full path of the existing EFI partition (e.g., /dev/sda1): " EFI_PARTITION_PATH
    echo "Using existing EFI partition at $EFI_PARTITION_PATH."

    echo "Creating swap partition ($SWAP_SIZE)..."
    parted -s "/dev/$DISK" mkpart primary linux-swap 1MiB "$SWAP_SIZE"
    SWAP_PARTITION="/dev/${DISK}2"

    echo "Creating root partition (ext4) using the remaining space..."
    parted -s "/dev/$DISK" mkpart primary ext4 "$SWAP_SIZE" 100%
    ROOT_PARTITION="/dev/${DISK}3"
else
    echo "Creating a new EFI partition ($EFI_SIZE)..."
    parted -s "/dev/$DISK" mkpart primary fat32 1MiB "$EFI_SIZE"
    parted -s "/dev/$DISK" set 1 esp on
    EFI_PARTITION="/dev/${DISK}1"

    echo "Creating swap partition ($SWAP_SIZE)..."
    parted -s "/dev/$DISK" mkpart primary linux-swap "$EFI_SIZE" "$((1024 + 8192))MiB"
    SWAP_PARTITION="/dev/${DISK}2"

    echo "Creating root partition (ext4) using the remaining space..."
    parted -s "/dev/$DISK" mkpart primary ext4 "$((1024 + 8192))MiB" 100%
    ROOT_PARTITION="/dev/${DISK}3"

    EFI_PARTITION_PATH=$EFI_PARTITION
fi

echo "Partitioning complete!"

echo "Formatting partition $ROOT_PARTITION..."
mkfs.ext4 -F "$ROOT_PARTITION"

echo "Formatting and enabling the swap partition..."
mkswap "$SWAP_PARTITION"
swapon "$SWAP_PARTITION"

if [[ "$HAS_EFI" != "yes" ]]; then
    echo "Formatting the new EFI partition to FAT32..."
    mkfs.fat -F 32 "$EFI_PARTITION_PATH"
fi

echo "Mounting the partitions..."
mount "$ROOT_PARTITION" /mnt

mkdir -p /mnt/boot/efi
echo "Mounting the EFI partition at /mnt/boot/efi..."
mount "$EFI_PARTITION_PATH" /mnt/boot/efi

echo ""
echo "The partitions have been created and mounted:"
echo "Root partition: $ROOT_PARTITION"
echo "Swap partition: $SWAP_PARTITION"
echo "EFI partition: $EFI_PARTITION_PATH"
echo ""

echo "Final disk layout:"
lsblk "/dev/$DISK"

echo ""
echo "------------------------------------"
echo "|            4 - MIRRORS           |"
echo "------------------------------------"
echo ""

read -p "Type the name of your country, to use the best mirrors available: " country
reflector --country $country --protocol https --sort rate --save /etc/pacman.d/mirrorlist
echo "$country selected successfully."

echo ""
echo "------------------------------------"
echo "|        5 - INSTALLATION           |"
echo "------------------------------------"
echo ""


sed -i '/\[multilib\]/,/Include.*mirrorlist/ s/^#//' /etc/pacman.conf
echo "Updating mirrors..."
pacman -Sy

echo "Installing base system packages..."
pacstrap /mnt base base-devel linux linux-firmware linux-headers nano sudo ntfs-3g git zsh grub networkmanager efibootmgr os-prober wget xorg-server plasma kde-applications lightdm docker jdk17-openjdk maven steam visual-studio-code-bin

echo "Generating fstab..."
genfstab -U /mnt >> /etc/fstab

echo "Saving timezone..."
ln -sf "/usr/share/zoneinfo/$TZ" /mnt/etc/localtime

echo "Setting default language to english, you can later set your desired language editing /etc/locale.gen and running locale-gen command. You also will need to edit /etc/locale.conf too."
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf

echo "Setting keyboard layout..."
echo "keymap=$KBD_LAYOUT" >> /mnt/etc/vconsole.conf

echo "Setting your hostname to arch"
echo "arch" > /mnt/etc/hostname
cat << 'HOSTS' > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
HOSTS

arch-chroot /mnt /bin/bash << EOF
  echo "Enabling Network Manager"
  systemctl enable NetworkManager

  echo "Setting root user's password"
  echo "root:$root_password" | chpasswd

  echo "Setting $username and password"
  useradd -m -G wheel -s /bin/bash $username
  echo "$username:$password" | chpasswd

  echo "Setting up sudo"
  sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

  echo "Updating mirrors"
  sed -i '/\[multilib\]/,/Include.*mirrorlist/ s/^#//' /etc/pacman.conf
  pacman -Sy
  
  echo "Installing microcode for your processor..."
  pacman -S $architecture-ucode --noconfirm

  echo "Setting up GRUB..."
  grub-install $EFI_PARTITION_PATH
  sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg

  echo "Setting up your GPU drivers"
  if [[ "$gpu" == "nvidia" ]]; then
    pacman -S nvidia nvidia-utils --noconfirm
  elif [[ "$gpu" == "amd" ]]; then
    pacman -S xf86-video-amdgpu --noconfirm
  else
    pacman -S xf86-video-intel --noconfirm
  fi

  echo "Installing yay (AUR helper)..."
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  chown -R "$username:$username" /tmp/yay
  sudo -u "$username" sh -c "cd /tmp/yay && makepkg -si --noconfirm"

  # Add user to docker group
  systemctl enable --now docker.service
  usermod -aG docker $username
EOF

echo "Unmounting and rebooting system..."
umount -R /mnt
sleep 10
systemctl reboot
