#!/bin/bash

function build_bsp() {
build=$1
machine=$2
bsp_version=$3

    setup_bsp_build ${build} ${machine} ${bsp_version}
    build_atf $machine
    build_optee $machine
    build_uboot $machine
}


function setup_bsp_build() {
build=$1
machine=$2
bsp_version=$3

    mkdir -p ${topdir}/build/${build}/bsp_sources; cd ${topdir}/build/${build}/bsp_sources

    log "> BSP sources: checking .."

    if [ ! -d trusted-firmware-a ]; then
        cd ${topdir}/build/${build}/bsp_sources
        log ">> atf: not found. cloning .."
        atf_srcrev=($(read_bsp_config ${bsp_version} atf_srcrev))
        atf_srcuri=($(read_bsp_config ${bsp_version} atf_srcuri))

        git_clone_repo ${atf_srcuri} ${atf_srcrev}

        log ">> atf: cloned"
    else
        log ">> atf: available"
    fi
    TFA_DIR=${topdir}/build/${build}/bsp_sources/trusted-firmware-a

    if [ ! -d optee_os ]; then
        cd ${topdir}/build/${build}/bsp_sources
        log ">> optee_os: not found. cloning .."
        optee_srcrev=($(read_bsp_config ${bsp_version} optee_srcrev))
        optee_srcuri=($(read_bsp_config ${bsp_version} optee_srcuri))

        git_clone_repo ${optee_srcuri} ${optee_srcrev}

        cd optee_os
        git checkout ${optee_srcrev} &>>"${LOG_FILE}"
        cd ..
        log ">> optee_os: cloned"
    else
        log ">> optee_os: available"
    fi
    OPTEE_DIR=${topdir}/build/${build}/bsp_sources/optee_os

    if [ ! -d ti-u-boot ]; then
        cd ${topdir}/build/${build}/bsp_sources
        log ">> ti-u-boot: not found. cloning .."
        uboot_srcrev=($(read_bsp_config ${bsp_version} uboot_srcrev))
        uboot_srcuri=($(read_bsp_config ${bsp_version} uboot_srcuri))

        git_clone_repo ${uboot_srcuri} ${uboot_srcrev}
        log ">> ti-u-boot: cloned"
        if [ -d ${topdir}/patches/ti-u-boot ]; then
            log ">> ti-u-boot: patching .."
            cd ti-u-boot
            git apply ${topdir}/patches/ti-u-boot/* &>>"${LOG_FILE}"
            cd ..
        fi
    else
        log ">> ti-u-boot: available"
    fi
    UBOOT_DIR=${topdir}/build/${build}/bsp_sources/ti-u-boot

    if [ ! -d ti-linux-firmware ]; then
        cd ${topdir}/build/${build}/bsp_sources
        log ">> ti-linux-firmware: not found. cloning .."
        linux_fw_srcrev=($(read_bsp_config ${bsp_version} linux_fw_srcrev))
        linux_fw_srcuri=($(read_bsp_config ${bsp_version} linux_fw_srcuri))

        git_clone_repo ${linux_fw_srcuri} ${linux_fw_srcrev}
        log ">> ti-linux-firmware: cloned"
    else
        log ">> ti-linux-firmware: available"
    fi
    FW_DIR=${topdir}/build/${build}/bsp_sources/ti-linux-firmware

    log "> BSP sources: cloned"
    log "> BSP sources: creating backup .."
    cd ${topdir}/build/${build}
    tar --use-compress-program="pigz --best --recursive | pv" -cf bsp_sources.tar.xz bsp_sources &>>"${LOG_FILE}"
    log "> BSP sources: backup created .."

    mkdir -p tisdk-${distro}-${machine}-boot
}

function build_atf() {
machine=$1

    cd $TFA_DIR
    target_board=($(read_machine_config ${machine} atf_target_board))
    make_args=($(read_machine_config ${machine} atf_make_args))

    log "> ATF: building .."
    make -j`nproc` ARCH=aarch64 CROSS_COMPILE=${cross_compile} PLAT=k3 TARGET_BOARD=${target_board} SPD=opteed ${make_args} &>>"${LOG_FILE}"
}

function build_optee() {
machine=$1

    cd ${OPTEE_DIR}
    platform=($(read_machine_config ${machine} optee_platform))
    make_args=($(read_machine_config ${machine} optee_make_args))
    # Workaround for toml not supporting empty values
    if [ ${make_args} == "." ]; then
        make_args=""
    fi

    log "> optee: building .."
    make -j`nproc` CROSS_COMPILE64=${cross_compile} CROSS_COMPILE=arm-none-linux-gnueabihf- PLATFORM=${platform} CFG_ARM64_core=y ${make_args} &>>"${LOG_FILE}"
}

function build_uboot() {
machine=$1

    uboot_r5_defconfig=($(read_machine_config ${machine} uboot_r5_defconfig))
    uboot_r5_defconfig=`echo $uboot_r5_defconfig | tr ',' ' '`
    uboot_a53_defconfig=($(read_machine_config ${machine} uboot_a53_defconfig))

    cd ${UBOOT_DIR}
    log "> uboot-r5: building .."
    make -j`nproc` ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- ${uboot_r5_defconfig} O=${UBOOT_DIR}/out/r5 &>>"${LOG_FILE}"
    make -j`nproc` ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=${UBOOT_DIR}/out/r5 BINMAN_INDIRS=${FW_DIR} &>>"${LOG_FILE}"
    cp ${UBOOT_DIR}/out/r5/tiboot3*.bin ${topdir}/build/${build}/tisdk-${distro}-${machine}-boot/ &>> ${LOG_FILE}

    cd ${UBOOT_DIR}
    log "> uboot-a53: building .."
    make -j`nproc` ARCH=arm CROSS_COMPILE=${cross_compile} ${uboot_a53_defconfig} O=${UBOOT_DIR}/out/a53 &>>"${LOG_FILE}"
    make -j`nproc` ARCH=arm CROSS_COMPILE=${cross_compile} BL31=${TFA_DIR}/build/k3/lite/release/bl31.bin TEE=${OPTEE_DIR}/out/arm-plat-k3/core/tee-pager_v2.bin O=${UBOOT_DIR}/out/a53 BINMAN_INDIRS=${topdir}/build/${build}/bsp_sources/ti-linux-firmware &>>"${LOG_FILE}"
    make -j`nproc` u-boot-initial-env O=${UBOOT_DIR}/out/a53 &>>"${LOG_FILE}"
    cp ${UBOOT_DIR}/out/a53/tispl.bin ${topdir}/build/${build}/tisdk-${distro}-${machine}-boot/ &>> ${LOG_FILE}
    cp ${UBOOT_DIR}/out/a53/u-boot.img ${topdir}/build/${build}/tisdk-${distro}-${machine}-boot/ &>> ${LOG_FILE}
    cp ${UBOOT_DIR}/out/a53/u-boot-initial-env ${topdir}/build/${build}/tisdk-${distro}-${machine}-rootfs/etc/

	case ${machine} in
		am62pxx-evm | am62xx-evm | am62xx-var-som | am62xx-lp-evm | am62xxsip-evm)
			cp ${UBOOT_DIR}/tools/logos/ti_logo_414x97_32bpp.bmp.gz ${topdir}/build/${build}/tisdk-${distro}-${machine}-boot/ &>> ${LOG_FILE}
			;;
	esac
}

git_clone_repo() {
	srcuri="$1"
	srcrev="$2"  # Can be a branch or a commit ID

	# Save the current directory
	original_dir=$(pwd)
    set -x
	# Clone the repository
	git clone "${srcuri}" &>>"${LOG_FILE}"
	cd "$(basename "${srcuri}" .git)" || return 1

	# Try to checkout the provided srcrev (branch or commit)
	if git checkout "${srcrev}" &>>"${LOG_FILE}"; then
		log "Successfully checked out ${srcrev}"
	else
		log "Error: Failed to check out ${srcrev}"
		cd "${original_dir}"
		return 1
	fi
    set +x
	cd "${original_dir}"
}
