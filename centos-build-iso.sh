#!/bin/bash

# centos-build-iso

#-------------------------------------------------------------------------------	Parameters

# selected flavor
ISO_FLAVOR=$1

# download mirror (1511 release = Centos 7.2)
ISO_URL=http://centos.mirror.transip.nl/7/isos/x86_64/CentOS-7-x86_64-Minimal-1611.iso
ISO_NAME=$(echo $ISO_URL|rev|cut -d/ -f1|rev)

# name of the target ISO file
ISO_TITLE=CentOS7-$ISO_FLAVOR


#-------------------------------------------------------------------------------	Helper functions

function yumpreload {
	# pre-download a package for unattended installation from iso

	TARGETDIR=$1
	shift
	# pre-download specified package
	while (( "$#" )); do
		yum install --downloadonly --downloaddir=$TARGETDIR/$1 $1
		shift
	done
}

#-------------------------------------------------------------------------------	Functions

function prepare_iso {	
	# load base image and modify boot menu

	# download baseimage if not present
	if [ ! -e $PWD/../$ISO_NAME ]
	then 
		curl -o ../$ISO_NAME $ISO_URL
	fi

	# create iso directory
	mkdir -p $PWD/iso

	# mount ISO to /media
	mount -o loop $PWD/../$ISO_NAME /media

	# copy base iso files from /media to working directory
	cp -r /media/* $PWD/iso
	cp /media/.treeinfo $PWD/iso
	cp /media/.discinfo $PWD/iso
	umount /media

	# remove menu default
	grep -v "menu default" $PWD/iso/isolinux/isolinux.cfg > $PWD/iso/isolinux/isolinux.cfg.new; \
		mv $PWD/iso/isolinux/isolinux.cfg.new $PWD/iso/isolinux/isolinux.cfg
	# add menu option ’Unattended Install’ to isolinux.cfg 
	cat $PWD/iso/isolinux/isolinux.cfg \
		| sed 's/label linux/label unattended\n  menu label ^Unattended Install\n  menu default\n  \
			kernel vmlinuz\n  append ks=cdrom:\/isolinux\/ui\/ks.cfg initrd=initrd.img\nlabel linux/' \
		| sed 's/timeout 600/timeout 100/'>$PWD/iso/isolinux/isolinux.cfg.new
	mv $PWD/iso/isolinux/isolinux.cfg.new $PWD/iso/isolinux/isolinux.cfg

	# create UnattendedInstall directory
	mkdir $PWD/iso/isolinux/ui

}

function download_updates {
	# download updates and extra packages

	# pre-install and install latest updates 
	yum clean all
	yum update --downloadonly --downloaddir=$PWD/iso/updates
	# install updates for identical baseline as during installation
	rpm -Uvh --replacepkgs $PWD/iso/updates/*.rpm	

}

function download_dependencies {
	# install dependencies like repositories 

	# pre-download and install epel-release as dependency
	yumpreload $PWD/iso/deps \
		epel-release
	# install epel-release
	yum install -y $PWD/iso/deps/epel-release/*.rpm

}

function download_extras {
	# download selected tools

	# pre-download network tools	
	yumpreload $PWD/iso/extras \
		arp-scan \
		bind-utils \
		iftop \
		nmap \
		tcpdump \
		traceroute \
		telnet \
		whois \
		wget

	# pre-install other tools
	yumpreload $PWD/iso/extras \
		bash-completion \
		git \
		lsof \
		mkisofs \
		mlocate \
		ntp \
		yum-utils
}

function add_kickstart_script {
	## add kickstart script

	cat > $PWD/iso/isolinux/ui/ks.cfg <<-'EOF'
	#version=RHEL7
	# System authorization information
	auth --enableshadow --passalgo=sha512
	logging --level=debug

	# Accept Eula
	eula --agreed

	# Do not use graphical install
	text
	skipx

	# Use CDROM installation media
	cdrom

	# Run the Setup Agent on first boot
	firstboot --enable
	ignoredisk --only-use=sda

	# Keyboard layouts
	keyboard --vckeymap=us --xlayouts='us'

	# System language
	lang en_US.UTF-8

	# Network information
	#network  --bootproto=dhcp --device=ens32 --ipv6=auto --activate
	network  --hostname=centos72.local

	# default credentials: root/toor
	rootpw --iscrypted $6$0JgAOt.nVDh9Abum$hoeKa2cfNDnlBZAsINa/BxApTQmb2TU9e/f7.4hrDvSj.T2.QE2HXanXmfLkVczfGtqGHM6tlbVTQM4Dlixtg0

	# Ansible user password: ansible/toor
	user --groups=wheel --name=ansible --password=$6$H6Um2a.4DrYrrzjx$zFc0fl4sydeM1I.7xlEq5Jg27Zy5.HtLj7ACi2gzkzEDDmke5CABlzUfPY6O.N.syt6WZTx4Tik17ai9GyIVW1 --iscrypted --gecos="ansible"

	# System timezone
	timezone Europe/Amsterdam --isUtc --nontp

	# selinux setting
	selinux --permissive

	# Disable chronyd
	services --disabled="chronyd"

	# --- Disk partitioning and configuration

	# System bootloader configuration
	bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=sda
	
	# Partition clearing information
	zerombr
	clearpart --all --initlabel --drives=sda

	# Disk partitioning information

	# Partition creation
	part /boot --fstype="xfs" --ondisk=sda --size=1024
	part / --fstype="xfs" --ondisk=sda --size=8192
	part /tmp --fstype="xfs" --ondisk=sda --size=1024
	part /srv/storage/sata/0 --fstype="xfs" --ondisk=sda --size=1024 --grow

	%packages --nobase
	@core
	openssh-server
	%end
	reboot --eject

	%post --log=/root/ks-post.log
	
	# Stuff to do after kickstart completes
	cd /etc/sysconfig/network-scripts
	for i in `ls ifcfg-eth*`
	do
	  interface=`echo $i | sed 's/ifcfg-//'`
	  sed -i '/HWADDR/c\DEVICE='$interface'' $i
	done

	for i in `ls ifcfg-ens*`
	do
	  interface=`echo $i | sed 's/ifcfg-//'`
	  sed -i '/HWADDR/c\DEVICE='$interface'' $i
	done

	mkdir /root/.ssh
	chmod 700 /root/.ssh
	cat << STOP > /root/.ssh/authorized_keys
	ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw0Omn2jWn/LznyVSgOlh1bCvL9X7vSu3IMWkQEUsTkKzg7cTd1dr5tr89BXVlvIBu6g1Ai9Q9B+2d/77pXrw116PhOLJzoazn2YNPukFDCX0Um25481jS5/4fE/0BytthEWTt2oZVMI7NQuM08NC0FHMZHufMQYxyZ4UzAcy6N2/B1jT3QkTmbZoraVlTHTReCA+wvA5jiw90kiqrRdaue78cZo5gEFlQ0B4mpRIs1E02SBxHs4vD+t+xQWMxXPToarg5Lzpg1/KWqI/OUVdP63YKJWY7Bcj2GkyyhsfA8LnQOf2n/J6litDXjk8dNnzc0KHsVaFacNbI3XwSQjYP ansible
	STOP
	chmod 600 /root/.ssh/authorized_keys
	
	mkdir /home/ansible/.ssh
	chmod 700 /home/ansible/.ssh
	cat << STOP > /home/ansible/.ssh/authorized_keys
	ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw0Omn2jWn/LznyVSgOlh1bCvL9X7vSu3IMWkQEUsTkKzg7cTd1dr5tr89BXVlvIBu6g1Ai9Q9B+2d/77pXrw116PhOLJzoazn2YNPukFDCX0Um25481jS5/4fE/0BytthEWTt2oZVMI7NQuM08NC0FHMZHufMQYxyZ4UzAcy6N2/B1jT3QkTmbZoraVlTHTReCA+wvA5jiw90kiqrRdaue78cZo5gEFlQ0B4mpRIs1E02SBxHs4vD+t+xQWMxXPToarg5Lzpg1/KWqI/OUVdP63YKJWY7Bcj2GkyyhsfA8LnQOf2n/J6litDXjk8dNnzc0KHsVaFacNbI3XwSQjYP ansible
	STOP
	chmod 600 /home/ansible/.ssh/authorized_keys
	chown -R ansible:ansible /home/ansible/.ssh

	echo "ansible  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible


	yum -y clean all

	rm -f /etc/ssh/ssh_host*key*


	## configure settings


	# send a null packet to the server every minute to keep the ssh connection alive
	echo "ServerAliveInterval 60" >> /etc/ssh/ssh_config


	# mount with noatime to prevent excessive SSD wear
	cat /etc/fstab |sed 's/defaults/defaults,noatime/g' >/tmp/fstab; mv -f /tmp/fstab /etc/fstab

	# disable NetworkManager by default
	systemctl disable NetworkManager

	# disable FirewallD by default
	systemctl disable firewalld

	# disable IPv6
	cat >> /etc/sysctl.conf <<-"EOF2"
	net.ipv6.conf.all.disable_ipv6 = 1
	net.ipv6.conf.default.disable_ipv6 = 1
	EOF2
	# change setting here as well
	cat >> /etc/sysconfig/network <<-"EOF2"
	NETWORKING_IPV6=no
	EOF2
	# prevent breaking ssh x-forwarding with ipv6
	cat /etc/ssh/sshd_config | \
		sed 's/#AddressFamily/AddressFamily/g' | \
		sed 's/AddressFamily any/AddressFamily inet/g' | \
		sed 's/#ListenAddress/ListenAddress/g' |\
		grep -v "ListenAddress ::" \
		> /etc/ssh/.sshd_config; mv -f /etc/ssh/.sshd_config /etc/ssh/sshd_config

	%end

	# reboot the machine after installation
	reboot
	EOF
}


function create_iso {
	## create ISO file

	yum install -y mkisofs
	mkisofs -r -T -J \
		-V “CentOS-v7.2-$ISO_FLAVOR” \
		-b isolinux/isolinux.bin \
		-c isolinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		-o ~/$ISO_TITLE.iso \
		$PWD/iso/

	# delete iso. Disable this line to save time during development
	rm -rf $PWD/iso

	# show result
	echo $ISO_TITLE.iso is ready in your homedir
}


#---------------------------------------------------------------------------------  Main script
# build the selected iso flavor. Note that the indented statements are what separates the flavors from Vanilla.

case "$ISO_FLAVOR" in 
	vanilla)
		# create vanilla CentOS 7.2 image (only add kickstart for unattended install)

		# download and unpack base image
		prepare_iso
		# add kickstart script to iso
		add_kickstart_script 
		# create unattended install iso from workspace
		create_iso
		;;

	update)
		# create vanilla CentOS 7.2 image with latest updates

		# download and unpack base image
		prepare_iso
		# download updates
		download_updates
		# add kickstart script to iso
		add_kickstart_script 
		# create unattended install iso from workspace
		create_iso
		;;

	tools)
		# CentOS 7.2 image with latest updates and tools

		# download and unpack base image
		prepare_iso
		# download updates
		download_updates
		# download dependencies like repositories etc
		download_dependencies
		# download extra tools
		download_extras
		# add kickstart script to iso
		add_kickstart_script
		# create unattended install iso from workspace
		create_iso		
		;;

	*)
		# no parameter specified, show usage
		echo "Usage: $0 {vanilla|update|tools}"
		exit 1;
esac


#-------------------------------------------------------------------------------End
