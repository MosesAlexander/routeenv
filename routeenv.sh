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
YOCTO_PATH=/home/obsrwr/games/yocto/poky/build
OPENBSD_PATH=/home/obsrwr/bmound/savedvols/kernwork/openbsd

copy_images_openwrt () {
	mkdir -p env/openwrt
	cp -v ${OPENWRT_PATH}/bin/x86/openwrt-x86-64-vmlinuz env/openwrt/openwrt-kernel
	cp -v ${OPENWRT_PATH}/bin/x86/openwrt-x86-64-rootfs-ext4.img env/openwrt/rootfs0-openwrt.ext4
	cp -v --reflink env/openwrt/rootfs0-openwrt.ext4 env/openwrt/rootfs1-openwrt.ext4

}

copy_images_yocto () {
	mkdir -p env/yocto
	cp -v ${YOCTO_PATH}/tmp/deploy/images/qemux86-64/bzImage env/yocto/yocto-kernel
	cp -v ${YOCTO_PATH}/tmp/deploy/images/qemux86-64/core-image-full-cmdline-qemux86-64.ext4 env/yocto/rootfs0-yocto.ext4
	cp -v --reflink env/yocto/rootfs0-yocto.ext4 env/yocto/rootfs1-yocto.ext4
}

copy_images_openbsd () {
	mkdir -p env/openbsd
	cp -v ${OPENBSD_PATH}/openbsd.raw env/openbsd/rootfs0-openbsd
	cp -v --reflink env/openbsd/rootfs0-openbsd env/openbsd/rootfs1-openbsd
}

copy_images_all () {
	copy_images_openwrt
	copy_images_yocto
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
	error_check_sudo "ip link add extveth0 type veth peer name extveth1"
	error_check_sudo "ip link set veth1 netns outer_ns"
	error_check_sudo "ip link set extveth1 netns outer_ns"
	error_check_sudo "ip link set veth0 up"
	error_check_sudo "ip link set extveth0 up"
	error_check_sudo "ip netns exec outer_ns ip link set veth1 up"
	error_check_sudo "ip netns exec outer_ns ip link set extveth1 up"
	# the idea is to have 2 bridges in each network namespace,
	# one so the yocto host can communicate with the router,
	# the other so the routers can communicate with eachother.
	error_check_sudo "ip netns exec outer_ns brctl addbr wrtbridge1"
	error_check_sudo "ip netns exec outer_ns brctl addbr yoctobridge1"
	error_check_sudo "ip netns exec outer_ns brctl addbr extbridge1"
	error_check_sudo "ip netns exec outer_ns brctl addif wrtbridge1 veth1"
	error_check_sudo "ip netns exec outer_ns brctl addif extbridge1 extveth1"
	error_check_sudo "brctl addbr wrtbridge0"
	error_check_sudo "brctl addbr yoctobridge0"
	error_check_sudo "brctl addbr extbridge0"
	error_check_sudo "brctl addif wrtbridge0 veth0"
	error_check_sudo "brctl addif extbridge0 extveth0"
	# set bridges up
	error_check_sudo "ip link set dev wrtbridge0 up"
	error_check_sudo "ip link set dev yoctobridge0 up"
	error_check_sudo "ip link set dev extbridge0 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev wrtbridge1 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev extbridge1 up"
	error_check_sudo "ip netns exec outer_ns ip link set dev yoctobridge1 up"
}

cleanup_namespace_env () {
	sudo ip link set dev wrtbridge0 down
	sudo ip link set dev yoctobridge0 down
	sudo ip link set dev extbridge0 down
	sudo ip link del veth0
	sudo brctl delbr wrtbridge0
	sudo brctl delbr yoctobridge0
	sudo brctl delbr extbridge0
	sudo ip netns del outer_ns
}

create_network_env_ovs () {
	# veth device acting as a wire between the routers
	error_check_sudo "ip link add veth0 type veth peer name veth1"
	error_check_sudo "ip link set veth0 up"
	error_check_sudo "ip link set veth1 up"

	# create ovs switches and attach the wire between the routers
	error_check_sudo "ovs-vsctl add-br wrtbridge0"
	error_check_sudo "ovs-vsctl add-br yoctobridge0"
	error_check_sudo "ovs-vsctl add-br wrtbridge1"
	error_check_sudo "ovs-vsctl add-br yoctobridge1"
	error_check_sudo "ovs-vsctl add-port wrtbridge0 veth0"
	error_check_sudo "ovs-vsctl add-port wrtbridge1 veth1"

	# set bridges up
	error_check_sudo "ip link set dev wrtbridge0 up"
	error_check_sudo "ip link set dev yoctobridge0 up"
	error_check_sudo "ip link set dev wrtbridge1 up"
	error_check_sudo "ip link set dev yoctobridge1 up"
}

cleanup_network_env_ovs () {
	sudo ip link set dev wrtbridge0 down
	sudo ip link set dev wrtbridge1 down
	sudo ip link set dev veth0 down
	sudo ip link set dev veth1 down
	sudo ovs-vsctl del-port wrtbridge0 veth0
	sudo ovs-vsctl del-port wrtbridge1 veth1
	sudo ip link del veth0
	sudo ovs-vsctl del-br wrtbridge0
	sudo ovs-vsctl del-br wrtbridge1
	sudo ovs-vsctl del-br yoctobridge0
	sudo ovs-vsctl del-br yoctobridge1
}

cleanup_images_openwrt () {
	rm env/openwrt/*
}

cleanup_images_yocto () {
	rm env/yocto/*
}

cleanup_images_all () {
	cleanup_images_openwrt
	cleanup_images_yocto
}

OVSENV="0"

start_qemu () {
	echo "VM type: openwrt, yocto or openbsd"
	read VMTYPE

	echo "VM net namespace 0 or 1:"
	read NETNSNUM

	if [ -z $NETNSNUM ]; then
		echo "No number provided."
		exit 1
	fi

	if [ $NETNSNUM != "0" ] && [ $NETNSNUM != "1" ]; then
		echo "Invalid network namespace number, must be 0 or 1."
		exit 1
	fi

	if [ $OVSENV != "0" ]; then
		echo "OVS environment present."
		ovsprefix="ovs-"
	fi

	case "$VMTYPE" in
		openwrt)
			if [ ! -e env/openwrt/openwrt-kernel ] | [ ! -e env/openwrt/rootfs$NETNSNUM-openwrt.ext4 ]; then
				echo "ERROR: must provide kernel/rootfs images via -c parameter before attempting to boot"
				exit 1
			fi

			sudo qemu-system-x86_64 -kernel env/openwrt/openwrt-kernel \
					-drive file=env/openwrt/rootfs$NETNSNUM-openwrt.ext4,id=d0,if=none \
					-device ide-hd,drive=d0,bus=ide.0 -append "root=/dev/sda console=ttyS0" \
					-nographic -serial mon:stdio -enable-kvm \
					-cpu kvm64 -M q35 \
					-netdev tap,id=nic0,ifname=wrtyoc-tap$NETNSNUM,script=conf/helpers/${ovsprefix}qemu-ifup-yoctobridge$NETNSNUM,downscript=conf/helpers/${ovsprefix}qemu-ifdown-yoctobridge$NETNSNUM \
					-device virtio-net-pci,netdev=nic0 \
					-netdev tap,id=nic1,ifname=wrtwrt-tap$NETNSNUM,script=conf/helpers/${ovsprefix}qemu-ifup-wrtbridge$NETNSNUM,downscript=conf/helpers/${ovsprefix}qemu-ifdown-wrtbridge$NETNSNUM \
					-device virtio-net-pci,netdev=nic1 \
					-netdev tap,id=nic2,ifname=wrtext-tap$NETNSNUM,script=conf/helpers/${ovsprefix}qemu-ifup-extbridge$NETNSNUM,downscript=conf/helpers/${ovsprefix}qemu-ifdown-extbridge$NETNSNUM \
					-device virtio-net-pci,netdev=nic2


			;;
		yocto)
			if [ ! -e env/yocto/yocto-kernel ] | [ ! -e env/yocto/rootfs$NETNSNUM-yocto.ext4 ]; then
				echo "ERROR: must provide kernel/rootfs images via -c parameter before attempting to boot"
				exit 1
			fi

			sudo qemu-system-x86_64 -kernel env/yocto/yocto-kernel \
					-drive file=env/yocto/rootfs$NETNSNUM-yocto.ext4,id=d0,if=none \
					-device ide-hd,drive=d0,bus=ide.0 -append "root=/dev/sda console=ttyS0" \
					-nographic -serial mon:stdio -enable-kvm \
					-cpu kvm64 -M q35 \
					-netdev tap,id=nic0,ifname=yocwrt-tap$NETNSNUM,script=conf/helpers/${ovsprefix}qemu-ifup-yoctobridge$NETNSNUM,downscript=conf/helpers/${ovsprefix}qemu-ifdown-yoctobridge$NETNSNUM \
					-device virtio-net-pci,netdev=nic0
			;;
		openbsd)
			if [ ! -e env/openbsd/rootfs$NETNSNUM-openbsd ]; then
				echo "ERROR: must provide kernel/rootfs images via -c parameter before attempting to boot"
				exit 1
			fi

			# use the openwrt qemu helper scripts. if you're using openbsd as something 
			# other than a firewall, you're on drugs
			sudo qemu-system-x86_64 -drive file=env/openbsd/rootfs$NETNSNUM-openbsd,id=d0,if=none,format=raw \
					-device ide-hd,drive=d0,bus=ide.0 \
					-nographic -serial mon:stdio -enable-kvm \
					-cpu kvm64 -smp cpus=2 -m 512M \
					-netdev tap,id=nic0,ifname=wrtyoc-tap$NETNSNUM,script=conf/helpers/${ovsprefix}qemu-ifup-yoctobridge$NETNSNUM,downscript=conf/helpers/${ovsprefix}qemu-ifdown-yoctobridge$NETNSNUM \
					-device virtio-net-pci,netdev=nic0 \
					-netdev tap,id=nic1,ifname=wrtwrt-tap$NETNSNUM,script=conf/helpers/${ovsprefix}qemu-ifup-wrtbridge$NETNSNUM,downscript=conf/helpers/${ovsprefix}qemu-ifdown-wrtbridge$NETNSNUM \
					-device virtio-net-pci,netdev=nic1
			;;
		*)
			echo "Error, invalid VM type!"
			exit 1
	esac

}

save_yocto_network_conf () {
	mkdir yocdir0 yocdir1 2>/dev/null
	mkdir -p conf/yocto
	sudo mount -v env/yocto/rootfs0-yocto.ext4 yocdir0
	sudo mount -v env/yocto/rootfs1-yocto.ext4 yocdir1
	sudo cp -v yocdir0/etc/network/interfaces conf/yocto/interfaces0
	sudo cp -v yocdir1/etc/network/interfaces conf/yocto/interfaces1
	sudo cp -v yocdir0/etc/hostname conf/yocto/hostname0
	sudo cp -v yocdir1/etc/hostname conf/yocto/hostname1
	sync
	sudo umount -v  yocdir0 yocdir1
}

restore_yocto_network_conf () {
	mkdir yocdir0 yocdir1 2>/dev/null
	sudo mount -v env/yocto/rootfs0-yocto.ext4 yocdir0
	sudo mount -v env/yocto/rootfs1-yocto.ext4 yocdir1
	sudo cp -v conf/yocto/interfaces0 yocdir0/etc/network/interfaces
	sudo cp -v conf/yocto/interfaces1 yocdir1/etc/network/interfaces
	sudo cp -v conf/yocto/hostname0 yocdir0/etc/hostname
	sudo cp -v conf/yocto/hostname1 yocdir1/etc/hostname
	sync
	sudo umount -v yocdir0 yocdir1
}

save_openwrt_network_conf () {
	mkdir wrtdir0 wrtdir1 2>/dev/null
	mkdir -p conf/openwrt/config0 conf/openwrt/config1 2>/dev/null
	sudo mount -v env/openwrt/rootfs0-openwrt.ext4 wrtdir0
	sudo mount -v env/openwrt/rootfs1-openwrt.ext4 wrtdir1
	# static IP addresses, firewall rules, hostname
	sudo cp -v wrtdir0/etc/config/network conf/openwrt/config0/network
	sudo cp -v wrtdir1/etc/config/network conf/openwrt/config1/network
	sudo cp -v wrtdir0/etc/config/firewall conf/openwrt/config0/firewall
	sudo cp -v wrtdir1/etc/config/firewall conf/openwrt/config1/firewall
	sudo cp -v wrtdir0/etc/config/system conf/openwrt/config0/system
	sudo cp -v wrtdir1/etc/config/system conf/openwrt/config1/system
	sync
	sudo umount -v wrtdir0 wrtdir1
}

restore_openwrt_network_conf () {
	mkdir wrtdir0 wrtdir1 2>/dev/null
	sudo mount -v env/openwrt/rootfs0-openwrt.ext4 wrtdir0
	sudo mount -v env/openwrt/rootfs1-openwrt.ext4 wrtdir1
	sudo cp -v conf/openwrt/config0/network wrtdir0/etc/config/network
	sudo cp -v conf/openwrt/config1/network wrtdir1/etc/config/network
	sudo cp -v conf/openwrt/config0/firewall wrtdir0/etc/config/firewall
	sudo cp -v conf/openwrt/config1/firewall wrtdir1/etc/config/firewall
	sudo cp -v conf/openwrt/config0/system wrtdir0/etc/config/system
	sudo cp -v conf/openwrt/config1/system wrtdir1/etc/config/system
	sync
	sudo umount -v wrtdir0 wrtdir1
}

case "$1" in
	-cpall|--copy-images-all)
		echo "Copying images"
		copy_images_all
		;;
	-cpy|--copy-images-yocto)
		echo "Copying yocto rootfs images and kernel"
		copy_images_yocto
		;;
	-cpo|--copy-images-openwrt)
		echo "Copying openwrt rootfs images and kernel"
		copy_images_openwrt
		;;
	-cpbsd|--copy-images-openbsd)
		echo "Copying openbsd rootfs images"
		copy_images_openbsd
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
	-nso|--create-ovs-env)
		echo "Setting up ovs network environment"
		create_network_env_ovs
		;;
	-sncy|--save-network-conf-yocto)
		echo "Saving yocto network configuration"
		save_yocto_network_conf
		;;
	-rncy|--restore-network-conf-yocto)
		echo "Restoring yocto network configuration"
		restore_yocto_network_conf
		;;
	-snco|--save-network-conf-openwrt)
		echo "Saving openwrt network configuration"
		save_openwrt_network_conf
		;;
	-rnco|--restore-network-conf-openwrt)
		echo "Restoring openwrt network configuration"
		restore_openwrt_network_conf
		;;
	-q|--start-qemu)
		echo "Starting qemu"
		start_qemu
		;;
	-qo|--start-qemu-ovs)
		echo "Starting qemu with ovs environment"
		OVSENV="1"
		start_qemu
		;;
	-cliy|--clean-images-yocto)
		echo "Cleaning up yocto images"
		cleanup_images_yocto
		;;
	-clio|--clean-images-openwrt)
		echo "Cleaning up openwrt images"
		cleanup_images_openwrt
		;;
	-clia|--clean-images-all)
		echo "Cleaning up images"
		cleanup_images_all
		;;
	--clean-namespaces)
		echo "Cleaning up namespaces"
		cleanup_namespace_env
		;;
	--clean-network-env-ovs)
		echo "Cleaning up ovs network environment"
		cleanup_network_env_ovs
		;;
	--clean-all)
		echo "Removing images and namespaces"
		cleanup_images
		cleanup_namespace_env
		;;
	*)
		echo "Must supply one parameter:"
		echo "-q|--start-qemu (start qemu instance of openwrt or yocto)"
		echo "-qo|--start-qemu-ovs (start qemu using ovs qemu-ifup/down helper scripts)"
		echo "-cpall|--copy-images-all (copy kernel+rootfs for openwrt and yocto builds)"
		echo "-cpy|--copy-images-yocto (copy kernel+rootfs for yocto builds)"
		echo "-cpo|--copy-images-openwrt (copy kernel+rootfs for openwrt builds)"
		echo "-ns|--create-nsenv (create outer_ns net namespace with yocto and openwrt bridges)"
		echo "-nso|--create-ovs-env (create ovs network bridges)"
		echo "-sncy|--save-network-conf-yocto (save yocto network configuration from /etc/network/interfaces"
		echo "-rncy|--restore-network-conf-yocto (restore yocto network configuration to /etc/network/interfaces"
		echo "-snco|--save-network-conf-openwrt (save openwrt network/firewall/system configuration)"
		echo "-rnco|--restore-network-conf-openwrt (restore openwrt network/firewall/system configuration)"
		echo "For cleaning:"
		echo "-clia|--clean-images-all (remove all kernel and rootfs images)"
		echo "-cliy|--clean-images-yocto (remove yocto kernel and rootfs images"
		echo "-clio|--clean-images-openwrt (remove openwrt kernel and rootfs images"
		echo "--clean-namespaces (remove created network namespace+associated veth device and bridges)"
		echo "--clean-network-env-ovs (remove created ovs network bridges + veth devices)"
		echo "--clean-all (remove everything generated by this script)"
		exit 1
		;;
esac

