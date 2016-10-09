#!/bin/bash

OPENWRT_PATH=/home/obsrwr/bmound/savedvols/kernwork/openwrt-qemu/openwrt
YOCTO_PATH=/home/obsrwr/bmound/savedvols/kernwork/yocto/build

copy_images () {
	cp -v ${OPENWRT_PATH}/bin/x86/openwrt-x86-64-vmlinuz env/openwrt/openwrt-kernel
	cp -v ${OPENWRT_PATH}/bin/x86/openwrt-x86-64-rootfs-ext4.img env/openwrt/rootfs1-openwrt.ext4
	cp -v --reflink env/openwrt/rootfs1-openwrt.ext4 env/openwrt/rootfs2-openwrt.ext4
	cp -v ${YOCTO_PATH}/tmp/deploy/images/qemux86-64/bzImage env/yocto/yocto-kernel
	cp -v ${YOCTO_PATH}/tmp/deploy/images/qemux86-64/core-image-full-cmdline-qemux86-64.ext4 env/yocto/rootfs1-yocto.ext4
	cp -v --reflink env/yocto/rootfs1-yocto.ext4 env/yocto/rootfs2-yocto.ext4
}

error_check_sudo () {
	echo $1
	sudo $1
	if [[ $? -ne 0 ]]; then
		echo "Something went wrong"
		exit 1;
	fi
}

create_namespace_env () {
	error_check_sudo "ip netns add outer_ns"
	error_check_sudo "ip link add veth0 type veth peer name veth1"
	error_check_sudo "ip link set veth1 netns outer_ns"
	error_check_sudo "ip netns exec outer_ns brctl addbr wrtbridge0"
	error_check_sudo "ip netns exec outer_ns brctl addbr yoctobridge0"
	error_check_sudo "ip netns exec outer_ns brctl addif wrtbridge0 veth1"
	error_check_sudo "brctl addbr wrtbridge0"
	error_check_sudo "brctl addbr yoctobridge0"
	error_check_sudo "brctl addif wrtbridge0 veth0"
}

case "$1" in
	-c|--copy-images)
		echo "Copying images"
		copy_images
		;;
	-s|--set_paths)
		echo "Setting paths"
		;;
	-ns|--create-nsenv)
		echo "Setting ns env"
		create_namespace_env
		;;
	*)
		echo "Must supply one parameter:"
		echo "-c|--copy-images (copy kernel+rootfs for openwrt and yocto builds)"
		echo "-ns|--create-nsenv (create outer_ns net namespace with yocto and openwrt bridges)"
		exit 1
		;;
esac

