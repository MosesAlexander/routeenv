#!/bin/bash

# routeenv script to help with virtual route test environment setup
#
# Copyright (C) 2016 Alexandru Moise <00moses.alexander00@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
#      but WITHOUT ANY WARRANTY; without even the implied warranty of
#      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#      GNU General Public License for more details.
#
#      You should have received a copy of the GNU General Public License
#      along with this program; if not, write to the Free Software
#      Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

OPENWRT_PATH=/home/obsrwr/bmound/savedvols/kernwork/openwrt-qemu/openwrt
YOCTO_PATH=/home/obsrwr/bmound/savedvols/kernwork/yocto/build

copy_images () {
	mkdir -p env/openwrt env/yocto

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

cleanup_namespace_env () {
	sudo ip link del veth0
	sudo brctl delbr wrtbridge0
	sudo brctl delbr yoctobridge0
	sudo ip netns del outer_ns
}

cleanup_images () {
	rm env/*/*
}

start_qemu () {
	echo "MAC address should end with:"
	read MACEND
	if [ -z $MACEND ]; then
		echo "No number provided."
		exit 1;
	fi
	MACEND_VAL=$(echo "ibase=16; ${MACEND^^}" | bc)

	if [ $MACEND_VAL -gt 255 ]; then
		echo "Invalid number, must be a hexadecimal number no greater than ff"
		exit 1;
	fi

	echo "MAC is $MACEND"

	echo "VM type: openwrt or yocto:"
	read VMTYPE

	echo "VM net namespace 1 or 2:"
	read NETNSNUM

	if [ -z $NETNSNUM ]; then
		echo "No number provided."
		exit 1
	fi

	if [ $NETNSNUM != "1" ] && [ $NETNSNUM != "2" ]; then
		echo "Invalid network namespace number, must be 1 or 2."
		exit 1
	fi

	case "$VMTYPE" in
		openwrt)
			if [ ! -e env/openwrt/openwrt-kernel ] | [ ! -e env/yocto/rootfs$NETNSNUM-yocto.ext4 ]; then
				echo "ERROR: must provide kernel/rootfs images via -c parameter before attempting to boot"
				exit 1
			fi

			sudo qemu-system-x86_64 -kernel env/openwrt/openwrt-kernel \
					-drive file=env/openwrt/rootfs$NETNSNUM-openwrt.ext4,id=d0,if=none \
					-device ide-hd,drive=d0,bus=ide.0 -append "root=/dev/sda console=ttyS0" \
					-nographic -serial mon:stdio -enable-kvm -smp cpus=2 \
					-cpu host -M q35 -smp cpus=2 \
					-netdev bridge,br=wrtbridge0,id=hn0 -device e1000,netdev=hn0,id=nic1 \
					-netdev user,id=hn1 -device e1000,netdev=hn1,id=nic2
			;;
		yocto)
			if [ ! -e env/yocto/yocto-kernel ] | [ ! -e env/openwrt/rootfs$NETNSNUM-openwrt.ext4 ]; then
				echo "ERROR: must provide kernel/rootfs images via -c parameter before attempting to boot"
				exit 1
			fi

			sudo qemu-system-x86_64 -kernel env/yocto/yocto-kernel \
					-drive file=env/yocto/rootfs$NETNSNUM-yocto.ext4,id=d0,if=none \
					-device ide-hd,drive=d0,bus=ide.0 -append "root=/dev/sda console=ttyS0" \
					-nographic -serial mon:stdio -enable-kvm -smp cpus=2 \
					-cpu host -M q35 -smp cpus=2 \
					-netdev bridge,br=wrtbridge0,id=hn0 -device e1000,netdev=hn0,id=nic1 \
					-netdev user,id=hn1 -device e1000,netdev=hn1,id=nic2
			;;
		*)
			echo "Error, invalid VM type!"
			exit 1
	esac

}

case "$1" in
	-c|--copy-images)
		echo "Copying images"
		copy_images
		;;
	-s|--set_paths)
		#TODO will probably just have an env.conf file 
		#     to set all our host specific variables
		echo "Setting paths"
		echo "Not yet implemented."
		;;
	-ns|--create-nsenv)
		echo "Setting ns env"
		create_namespace_env
		;;
	-q|--start-qemu)
		echo "Starting qemu"
		start_qemu
		;;
	--clean-images)
		echo "Cleaning up images"
		cleanup_images
		;;
	--clean-namespaces)
		echo "Cleaning up namespaces"
		cleanup_namespace_env
		;;
	--clean-all)
		echo "Removing images and namespaces"
		cleanup_images
		cleanup_namespace_env
		;;
	*)
		echo "Must supply one parameter:"
		echo "-c|--copy-images (copy kernel+rootfs for openwrt and yocto builds)"
		echo "-ns|--create-nsenv (create outer_ns net namespace with yocto and openwrt bridges)"
		echo "-q|--start-qemu (start qemu instance of openwrt or yocto)"
		echo "--clean-images (remove kernel and rootfs images)"
		echo "--clean-namespaces (remove created network namespace+associated veth device and bridges)"
		echo "--clean-all (remove everything generated by this script)"
		exit 1
		;;
esac

