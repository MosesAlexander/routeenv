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
	# first, create the outer net namespace
	error_check_sudo "ip netns add outer_ns"
	# the veth devices will be used so the openwrt routers can
	# communicate with each other coming from separate net namespaces
	error_check_sudo "ip link add veth0 type veth peer name veth1"
	error_check_sudo "ip link set veth1 netns outer_ns"
	# the idea is to have 2 bridges in each network namespace,
	# one so the yocto host can communicate with the router,
	# the other so the routers can communicate with eachother.
	error_check_sudo "ip netns exec outer_ns brctl addbr wrtbridge1"
	error_check_sudo "ip netns exec outer_ns brctl addbr yoctobridge1"
	error_check_sudo "ip netns exec outer_ns brctl addif wrtbridge1 veth1"
	error_check_sudo "brctl addbr wrtbridge0"
	error_check_sudo "brctl addbr yoctobridge0"
	error_check_sudo "brctl addif wrtbridge0 veth0"
	# 3 types of tap devices as per their roles:
	# - router-to-router L2 communication
	# - router-to-yoctohost L2 communication
	# - yoctohost-to-router L2 communication
	error_check_sudo "ip tuntap add name wrtwrt-tap0 mode tap"
	error_check_sudo "ip tuntap add name wrtyoc-tap0 mode tap"
	error_check_sudo "ip tuntap add name yocwrt-tap0 mode tap"
	# outer_ns tap devices
	error_check_sudo "ip netns exec outer_ns ip tuntap add name wrtwrt-tap1 mode tap"
	error_check_sudo "ip netns exec outer_ns ip tuntap add name wrtyoc-tap1 mode tap"
	error_check_sudo "ip netns exec outer_ns ip tuntap add name yocwrt-tap1 mode tap"
	# wire the bridges for both network namespaces
	error_check_sudo "brctl addif wrtbridge0 wrtwrt-tap0"
	error_check_sudo "brctl addif yoctobridge0 wrtyoc-tap0"
	error_check_sudo "brctl addif yoctobridge0 yocwrt-tap0"
	error_check_sudo "ip netns exec outer_ns brctl addif wrtbridge1 wrtwrt-tap1"
	error_check_sudo "ip netns exec outer_ns brctl addif yoctobridge1 wrtyoc-tap1"
	error_check_sudo "ip netns exec outer_ns brctl addif yoctobridge1 yocwrt-tap1"
	# raise them up
	error_check_sudo "ip link set dev wrtwrt-tap0 up"
	error_check_sudo "ip link set dev wrtyoc-tap0 up"
	error_check_sudo "ip link set dev yocwrt-tap0 up"
	error_check_sudo "ip link set dev wrtbridge0 up"
	error_check_sudo "ip link set dev yoctobridge0 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev wrtbridge1 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev yoctobridge1 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev wrtwrt-tap1 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev wrtyoc-tap1 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev yocwrt-tap1 up"
}

get_interfaces_fds () {
	wrtwrttap0_fd=$(ip addr | grep wrtwrt-tap0 | awk '{print $1}')
	wrtwrttap0_fd=`echo $wrtwrttap0_fd | awk '{print substr($wrtwrttap0_fd, 0, length($wrtwrttap0_fd)-1)}'`
	wrtyoctap0_fd=$(ip addr | grep wrtyoc-tap0 | awk '{print $1}')
	wrtyoctap0_fd=`echo $wrtyoctap0_fd | awk '{print substr($wrtyoctap0_fd, 0, length($wrtyoctap0_fd)-1)}'`
	yocwrttap0_fd=$(ip addr | grep yocwrt-tap0 | awk '{print $1}')
	yocwrttap0_fd=`echo $yocwrttap0_fd | awk '{print substr($yocwrttap0_fd, 0, length($yocwrttap0_fd)-1)}'`
	wrtwrttap1_fd=$(sudo ip netns exec outer_ns ip addr | grep wrtwrt-tap1 | awk '{print $1}')
	wrtwrttap1_fd=`echo $wrtwrttap1_fd | awk '{print substr($wrtwrttap1_fd, 0, length($wrtwrttap1_fd)-1)}'`
	wrtyoctap1_fd=$(sudo ip netns exec outer_ns ip addr | grep wrtyoc-tap1 | awk '{print $1}')
	wrtyoctap1_fd=`echo $wrtyoctap1_fd | awk '{print substr($wrtyoctap1_fd, 0, length($wrtyoctap1_fd)-1)}'`
	yocwrttap1_fd=$(sudo ip netns exec outer_ns ip addr | grep yocwrt-tap1 | awk '{print $1}')
	yocwrttap1_fd=`echo $yocwrttap1_fd | awk '{print substr($yocwrttap1_fd, 0, length($yocwrttap1_fd)-1)}'`

}

cleanup_namespace_env () {
	sudo ip link set dev wrtbridge0 down
	sudo ip link set dev yoctobridge0 down
	sudo ip link del veth0
	sudo brctl delbr wrtbridge0
	sudo brctl delbr yoctobridge0
	sudo ip link del wrtwrt-tap0
	sudo ip link del wrtyoc-tap0
	sudo ip link del yocwrt-tap0
	sudo ip netns del outer_ns
}

cleanup_images () {
	rm env/*/*
}

start_qemu () {
	# gotta get the dynamically assigned fds for all tap interfaces
	# so that we can assign them to VM instance
	get_interfaces_fds

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

			if [ $NETNSNUM == "1" ]; then
				INFD_YOC=$wrtyoctap0_fd
				INFD_WRT=$wrtwrttap0_fd
			elif [ $NETNSNUM == "2" ]; then
				INFD_YOC=$wrtyoctap1_fd
				INFD_WRT=$wrtwrttap1_fd
			fi

			sudo qemu-system-x86_64 -kernel env/openwrt/openwrt-kernel \
					-drive file=env/openwrt/rootfs$NETNSNUM-openwrt.ext4,id=d0,if=none \
					-device ide-hd,drive=d0,bus=ide.0 -append "root=/dev/sda console=ttyS0" \
					-nographic -serial mon:stdio -enable-kvm \
					-cpu host -M q35 \
					-netdev tap,id=hn0,fd=$INFD_YOC \
					-device e1000,netdev=hn0,id=nic0 \
					-netdev tap,id=hn1,fd=$INFD_WRT \
					-device e1000,netdev=hn1,id=nic1
			;;
		yocto)
			if [ ! -e env/yocto/yocto-kernel ] | [ ! -e env/openwrt/rootfs$NETNSNUM-openwrt.ext4 ]; then
				echo "ERROR: must provide kernel/rootfs images via -c parameter before attempting to boot"
				exit 1
			fi

			if [ $NETNSNUM == "1" ]; then
				INFD=$yocwrttap0_fd
			elif [ $NETNSNUM == "2" ]; then
				INFD=$yocwrttap1_fd
			fi

			sudo qemu-system-x86_64 -kernel env/yocto/yocto-kernel \
					-drive file=env/yocto/rootfs$NETNSNUM-yocto.ext4,id=d0,if=none \
					-device ide-hd,drive=d0,bus=ide.0 -append "root=/dev/sda console=ttyS0" \
					-nographic -serial mon:stdio -enable-kvm \
					-cpu host -M q35 \
					-netdev tap,id=hn0,fd=$INFD \
					-device e1000,netdev=hn0,id=nic0
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

