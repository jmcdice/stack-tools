#!/bin/bash
# Start an automated stacki install. 
# Make sure this is installed for HP hardware: https://pythonhosted.org/python-hpilo/index.html
# Joey <joey.mcdonald@nokia.com>

# Modify as needed for your env
iso_file='stacki-custom_iso.iso'
cluster='stacki-poc'
acid_ip=$(ip a s eth0 | perl -lane 'print $1 if (/inet (.*?)\//)')
ilo_user='hp'
ilo_pass='password'
fe_ilo='172.29.36.112'
compute_ilos=( 172.29.36.113 172.29.36.115 172.29.36.116 172.29.36.107 )
fe_public_ip='172.29.55.10'


function clean_ssh_known_hosts() {

   fe=$1
   cat /root/.ssh/known_hosts | grep -v $fe > /tmp/known_hosts
   mv /tmp/known_hosts /root/.ssh/known_hosts
   chmod 600 /root/.ssh/known_hosts
}

function repack_iso() {

   echo -n "Creating custom frontend ISO: "
   cd /export/stack_iso/ && \
   mkisofs -V 'CloudBand - Disk 1' \
      -b isolinux/isolinux.bin -c isolinux/boot.cat \
      -no-emul-boot -boot-load-size 6 -boot-info-table \
      -r -T -f -input-charset utf-8 -m initrd -m cb-fe -o /var/www/html/iso/stacki/$iso_file . &> /dev/null
   echo "Ok"
}

function power_off() {

   cpt=$1

   echo -n "Powering down $cpt: "
   sleep 3
   ipmit="/usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $cpt chassis power off"
   $ipmit &> /dev/null
   while test $? -gt 0; do
      sleep 5
      $ipmit &> /dev/null
   done

   echo "Ok"
}

function iso_boot_frontend() {

   ip=$1

   cd /export/ci/tools/ci/

   # Eject ISO if inserted.
   ./hpilo_cli -l $ilo_user -p $ilo_pass $ip get_vm_status |grep image_inserted | grep -iq yes
   if [ $? -eq '0' ]; then
      echo -n "Ejecting a mounted ISO: "
      ./hpilo_cli -l $ilo_user -p $ilo_pass $ip eject_virtual_media device=cdrom &> /dev/null
      echo "Ok"
   fi

   echo -n "Powering down $ip: "
   /usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $ip chassis power off &> /dev/null
   sleep 10
   echo "Ok"

   echo -n "Inserting Virtual Media: "
   ./hpilo_cli -l $ilo_user -p $ilo_pass $ip insert_virtual_media device=CDROM \
      image_url=http://$acid_ip/iso/stacki/$iso_file &> /dev/null
   echo "Ok"

   echo -n "Setting boot priority: "
   ./hpilo_cli -l $ilo_user -p $ilo_pass $ip set_vm_status device=cdrom boot_option=boot_once write_protect=True &> /dev/null
   ./hpilo_cli -l $ilo_user -p $ilo_pass $ip set_one_time_boot device=cdrom &> /dev/null
   ./hpilo_cli -l $ilo_user -p $ilo_pass $ip set_persistent_boot devices=CDROM,NETWORK,HDD,USB,FLOPPY &> /dev/null
   sleep 10
   echo "Ok"

   echo -n "Powering up $ip: "
   /usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $ip chassis power on &> /dev/null
   sleep 3
   echo "Ok"
}

function wait_for_ssh() {

   fe=$1
   cluster=$2

   echo -n "Waiting for $cluster frontend to install: "

   ssh="ssh -q -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $fe 'hostname' 2>&1 | grep -q $cluster"
   $ssh
   while test $? -gt 0; do
      sleep 5
      $ssh
   done
   clean_ssh_known_hosts $fe

   echo "Ok"
}

function add_stacki_pallet() {

   fe=$1

   echo -n "Adding Stacki Pallet: "
   scp -q /var/www/html/iso/stacki/stacki-3.1-7.x.x86_64.disk1.iso $fe:
   ssh $fe 'stack add pallet stacki-3.1-7.x.x86_64.disk1.iso' &> /dev/null
   sleep 10
   echo "Ok"
}

function run_fe_config() {

   fe=$1
   scp -q configure_fe.sh $fe:
   ssh $fe 'bash /root/configure_fe.sh'
}

function pxeboot() {

   compute=$1
   cd /export/ci/tools/ci/

   echo -n "Powering down $compute: "
   /usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $compute chassis power off &> /dev/null
   sleep 10
   echo "Ok"

   compute=$1
   echo -n "Setting pxe boot for $compute: "
   ./hpilo_cli -l $ilo_user -p $ilo_pass $compute set_persistent_boot devices=NETWORK,HDD,USB,FLOPPY &> /dev/null
   sleep 5
   echo "Ok"

   echo -n "Powering up $compute: "
   /usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $compute chassis power on &> /dev/null
   echo "Ok"
}

clean_ssh_known_hosts $fe_public_ip
repack_iso
for ilo in ${compute_ilos[@]}; do
   power_off $ilo
done

iso_boot_frontend $fe_ilo
wait_for_ssh $fe_public_ip $cluster
add_stacki_pallet $fe_public_ip
run_fe_config $fe_public_ip

# PXE boot computes
for ilo in ${compute_ilos[@]}; do
   pxeboot $ilo
done

## Do more stuff here.
