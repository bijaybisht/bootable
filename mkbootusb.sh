
usage() 
{
  echo 
  echo Error: $1
  echo "
Usage: `basename $0` -d <dev> -i <iso>

  parameters
  ----------
       <dev> : USB dev name e.g /dev/sdb. Use dmesg to find out.
       <iso> : ISO that needs to made into bootable USB.

"
  exit
}

debug() {
	echo '---------------------------------' 
	echo "Log : $*"
	echo '---------------------------------' 
	sleep 1
}


getoptions()
{
	 
  while getopts ":d:i:" opt 2>/dev/null; do
    case $opt in
      d)
        DEV=$OPTARG
        ;;
      i)
        ISO=$OPTARG
        ;;
      \?)
        usage "Invalid option: -$OPTARG"
        ;;
      :)
        usage "Option -$OPTARG requires an argument."
        ;;
    esac
  done
  shift $((OPTIND - 1))
}

getoptions $@

debug "Creating working directories"
mkdir -p temp usb/extlinux usb/temp

debug "Mounting iso"
mount $ISO temp -o loop

debug "Copying files from iso"
cp -a temp/isolinux/* usb/extlinux/


debug "Setting permissions on the usb [working] folder"
chmod -R u+rw usb

debug "Changing dir to usb [working] folder"
cd usb

debug "Copying menu.c32 which comes for the syslinux... package. Not sure if it is getting used"
cp /usr/share/syslinux/menu.c32 extlinux/

debug "Since we are going to use extlinux which comes from the extlinux... package. Copying isolinux.cfg to extlinux.cfg + extra"
mv extlinux/isolinux.cfg extlinux/extlinux.conf
rm -fr extlinux/isolinux.bin extlinux/TRANS.TBL 

debug "Copying customised extlinux.cfg"
cp ../extlinux.conf extlinux/extlinux.conf

debug "Creating a usb image file on disk for now of size bs * count"
dd if=/dev/zero of=./custom-boot.img bs=1024 count=60000

debug "Finding the available /dev/loop<x> available"
loopid=$(losetup -f)

debug "Setting up the usb image file as a loop device"
losetup $loopid ./custom-boot.img 

debug "Creating a primary partion 1 and makeing it bootable on the new mapped loop device"
fdisk $loopid <<FDISK
n
p
1


a
1
p
w

FDISK
sync
debug "Creating the mbr by dumping [dd] the mbr.bin on the mapped loop device"
dd if=/usr/share/syslinux/mbr.bin of=$loopid

debug "Mapping the partitions on the mapped loop device using kpartx so thatt we can format"
kpartx -av $loopid

debug "Creating an ext2 file system on primary partition 1 of the mapped loop device"
mkfs.ext2 -m 0 -L "USBBOOT" /dev/mapper/$(basename $loopid)p1

debug "Mounting the primary partition 1 of the mapped loop device"
mount /dev/mapper/$(basename $loopid)p1 temp

debug "Cleaning the primary partition 1 of the mapped loop device"
rm -fr temp/lost+found/

debug "Copying the prepared files in usb/extlinux folder to the primary partition"
cp -a extlinux/* temp/

#cp -a ../ks.cfg temp/

debug "Extlinuxing the primary partition 1."
extlinux --install temp

debug "Unmounting the primary partition 1."
umount temp

debug "U mapping the partitions on the loop device"
kpartx -dv $loopid

debug "U mapping the loop device"
losetup -d $loopid

debug "Sync the changes"
sync

debug "TODO: [cleanup, step can be avoided] Unmount the usb"
umount /mnt/usb
umount /mnt/usb1

debug "NOW dump the prepared image on the real device."
dd if=./custom-boot.img of=$DEV


debug "Creating another primary partition 2, for dumping the install image i.e. the iso completely"
fdisk $DEV <<FDISK
n
p
2


w

FDISK
sync

debug "mkfs.ext2 on /dev/sdb2"

debug "Creating an ext2 file system on primary partition 2 of the mapped loop device"
mkfs.ext2 -m 0 -L "USBISO" ${DEV}2

debug "Mount the iso"
debug "Mount ${DEV}2 to /mnt/usb2"
mount ${DEV}2 /mnt/usb
debug "Copy the contents of the iso to /dev/sdb2"
cp -a ../temp/* /mnt/usb/
cp ../ks.cfg /mnt/usb
debug "Unmounting iso"
umount ../temp

#debug "Now mount the usb parition 1"
#mount ${DEV}1 /mnt/usb1
#cd ..
#mkdir initrd.img-contents
#cd initrd.img-contents
#xz -dc /mnt/usb1/initrd.img | cpio -id
#cp ../ks.cfg .
#find . | cpio -c -o | xz -9 --format=lzma > /mnt/usb1/initrd.img
#umount /mnt/usb1

#debug "Use the udevadm to find about your usb device"
#udevadm info -a -p $(udevadm info -q path -n /dev/sdb)
#debug "Adding 10-usb.rules for adding the usb device"
# 10-usb.rules
# KERNEL=="sd*", SUBSYSTEMS=="scsi", ATTRS{model}=="USB Flash Disk ", NAME+="usbhd%n"
