#!/bin/bash -e

# Constants
readonly file_script="$(basename "$0")"
readonly dir_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Input arguments
TOPDIR=${dir_script}/../..
BUILD=$1
BUILDPATH=${TOPDIR}/build

# Ensure the BUILD variable is provided
if [[ -z "$BUILD" ]]; then
    echo "Usage: $file_script <build-directory-name>"
    exit 1
fi

# Ensure the build directory exists
if [[ ! -d "${BUILDPATH}/${BUILD}" ]]; then
    echo "Build directory does not exist: $BUILDPATH"
    exit -1
fi

# Create the wic
cd ${TOPDIR}
sudo ./create-wic.sh $BUILD
cd -

# Locate the .wic.zst file dynamically
wic_zst_file=$(find "${BUILDPATH}/${BUILD}" -maxdepth 1 -name "*.wic.zst" | head -n 1)

# Check if the .wic.zst file exists
if [[ ! -f "$wic_zst_file" ]]; then
    echo "Error: .wic.zst file not found in ${BUILDPATH}/${BUILD}."
    exit 1
fi

# Create a temporary directory to decompress the .wic.zst file
temp_wic_dir=$(mktemp -d)
echo "Decompressing $wic_zst_file to $temp_wic_dir..."
zstd -d "$wic_zst_file" -o "$temp_wic_dir/tisdk-debian-bookworm-am62xx-var-som.wic"

# Get the WIC file path
wic_file="$temp_wic_dir/tisdk-debian-bookworm-am62xx-var-som.wic"

# Get the second partition of the WIC file
echo "Getting second partition info for $wic_file..."
loop_device=$(sudo losetup -Pf --show "$wic_file")
second_partition="${loop_device}p2"  # Assuming second partition is p2

# Create a temporary mount point
temp_mount=$(mktemp -d)
echo "Mounting second partition $second_partition at $temp_mount..."
sudo mount "$second_partition" "$temp_mount"

echo "Copying installation files to $temp_mount"
sudo mkdir -p ${temp_mount}/opt/images/Debian/boot

# Dynamically get the rootfs and boot filenames
rootfs_file=$(ls ${BUILDPATH}/${BUILD}/*rootfs.tar.zst)
boot_file=$(ls ${BUILDPATH}/${BUILD}/*boot.tar.xz)

# Copy the rootfs image
sudo cp "${rootfs_file}" "${temp_mount}/opt/images/Debian/rootfs.tar.zst"

# Install the bootloader
sudo tar -xzf "${boot_file}" --strip-components=1 -C "${temp_mount}/opt/images/Debian/boot/"

# Add an empty uEnv.txt since one is not included by default but expected by install_debian.sh
echo "" | sudo tee ${temp_mount}/opt/images/Debian/boot/uEnv.txt > /dev/null

# Fetch and patch install_debian.sh
sudo curl -L https://raw.githubusercontent.com/varigit/meta-variscite-sdk-ti/ab984c96d19358a160dd61ad43b587a8731e9833/scripts/variscite/am6_install_yocto.sh -o ${temp_mount}/usr/sbin/install_debian.sh
sudo patch ${temp_mount}/usr/sbin/install_debian.sh < ${dir_script}/patches/0001-am6_install_yocto.sh-Strip-top-directory-from-rootfs.patch
sudo chmod +x ${temp_mount}/usr/sbin/install_debian.sh

# Fetch echos.sh
sudo curl -L https://raw.githubusercontent.com/varigit/meta-variscite-sdk-ti/ab984c96d19358a160dd61ad43b587a8731e9833/scripts/variscite/echos.sh -o ${temp_mount}/usr/bin/echos.sh

# Unmount and clean up
echo "Unmounting..."
sudo umount "$temp_mount"
sudo losetup -d "$loop_device"

# Remove the temporary mount point
echo "Removing temporary mount point $temp_mount..."
rmdir "$temp_mount"

# Compress to a new file named 'tisdk-debian-bookworm-am62xx-var-som-recovery-image.wic.zst'
new_wic_zst_file="${BUILDPATH}/${BUILD}/tisdk-debian-bookworm-am62xx-var-som-recovery-image.wic.zst"
echo "Recompressing to $new_wic_zst_file..."
sudo zstd "$wic_file" -o "$new_wic_zst_file" -f

# Remove the temporary directory for the decompressed WIC file
echo "Removing temporary directory $temp_wic_dir..."
rm -rf "$temp_wic_dir"

echo "Created ${new_wic_zst_file}"
