#!/bin/bash -e

readonly FILE_SCRIPT="$(basename "$0")"
readonly DIR_SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
readonly BUILDPATH="${DIR_SCRIPT}/../../build"
readonly BUILD="$1"

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

SWU_DIR=$(mktemp -d)

# Copy the required files into the temporary directory
cp ${DIR_SCRIPT}/sw-description "$SWU_DIR"
cp ${DIR_SCRIPT}/update.sh "$SWU_DIR"

# Copy rootfs dynamically
cp ${BUILDPATH}/${BUILD}/*-rootfs.tar.zst "$SWU_DIR/rootfs.tar.zst"

# Copy boot files dynamically
tar -xzf ${BUILDPATH}/${BUILD}/*-boot.tar.xz --strip-components=1 -C "$SWU_DIR"

# Create the .swu file
cd "$SWU_DIR"
FILES="sw-description sw-description.sig update.sh tiboot3.bin tispl.bin u-boot.img rootfs.tar.zst"

# Calculate SHA256 sums and update the sw-description file
for file in $FILES; do
    if [[ -f "${SWU_DIR}/$file" ]]; then
        SHA256=$(sha256sum "${SWU_DIR}/$file" | awk '{print $1}')
        sed -i "/filename = \"$file\";/a \\\t\t\t\tsha256 = \"$SHA256\";" "${SWU_DIR}/sw-description"
    else
        echo "Warning: $file not found, skipping SHA256 addition."
    fi
done

# Create a CMS signature for sw-description
openssl cms -sign -in  ${SWU_DIR}/sw-description -out ${SWU_DIR}/sw-description.sig -signer ${DIR_SCRIPT}/../swupdate/mycert.cert.pem \
        -inkey ${DIR_SCRIPT}/../swupdate/mycert.key.pem -outform DER -nosmimecap -binary

# Generate the swu file
for i in $FILES; do
        echo $i;done | cpio -ov -H crc > ../${BUILD}.swu

mv ../${BUILD}.swu .
cd -

# Move the final image
sudo mv ${SWU_DIR}/${BUILD}.swu ${BUILDPATH}/${BUILD}/${BUILD}.swu

# Remove the temporary directory
rm -rf "$SWU_DIR"

echo "SWU file created successfully: ${BUILDPATH}/${BUILD}/${BUILD}.swu"
