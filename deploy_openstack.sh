#!/bin/bash
#
# Deploy a stacki cluster inside openstack.
# 
# Joey <joey.mcdonald@nokia.com>

# Change these values to match your environment

public_network='floating'      # Your pool of floating IP's in neutron.
guest_vlans=(48 49)            # Need 2 VLAN's here for our private networks.
cluster='cluster-1.stacki.com' # The name of this cluster
domain='stacki.com'	       # Domain name
rootpw=$(openssl passwd -1 -salt sdf stacki123) # Root password is: stacki123

function check_os_creds() {

   echo -n "Checking OpenStack Credentials: "
   nova list &> /dev/null
   if [ $? != 0 ]; then
      echo "Failed"
      echo "Please source OpenStack credentials."
      exit 255
   else
      echo "Ok"
   fi
}

function install_centos() {

   echo -n "Checking for CentOS image: "
   nova image-list | grep -q CentOS-7-GenericCloud
   if [ $? != 0 ]; then
      echo "Installing"
      wget -q http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1603.qcow2 &> /dev/null
      glance image-create --name='CentOS-7-GenericCloud' --is-public=true \
         --container-format=bare --disk-format=qcow2 < CentOS-7-x86_64-GenericCloud-1603.qcow2 &> /dev/null

      nova image-list|grep CentOS-7-GenericCloud|grep -q ACTIVE
      if [ $? != 0 ]; then
         echo "Failed to install CentOS 7 Cloud Image. Bummer."  
         exit 227
      fi
   else
      echo "Ok"
   fi
}

function create_networks() {

   echo -n "Checking for guest networks: "
   neutron net-list | grep -q stacki-private

   if [ $? != '0' ]; then

      echo "Installing"

      region=$(openstack endpoint list|grep neutron |awk '{print $4}')
      # Private network
      neutron net-create --provider:physical_network $region \
         --provider:network_type vlan --provider:segmentation_id ${guest_vlans[0]} stacki-private &> /dev/null
      neutron subnet-create stacki-private 10.1.1.0/24 --disable-dhcp --name stacki-private-subnet &> /dev/null

      # Public Network
      neutron net-create --provider:physical_network $region \
         --provider:network_type vlan --provider:segmentation_id ${guest_vlans[1]} stacki-public &> /dev/null
      neutron subnet-create stacki-public 192.168.0.0/24 --name stacki-public-subnet &> /dev/null

      neutron subnet-list|grep -q stacki-public-subnet
      if [ $? != 0 ]; then
         echo "Failed to create tenant networks. Bummer." 
         exit 258
      fi

   else
      echo "Ok"
   fi
}

function create_virtual_router() {

   echo -n "Checking for a virtual router: "

   neutron router-list | grep -q stacki-router
   if [ $? != '0' ]; then
      echo "Installing"

      neutron router-create stacki-router  &> /dev/null
      neutron router-gateway-set stacki-router $public_network &> /dev/null
      neutron router-interface-add stacki-router stacki-public-subnet &> /dev/null

      neutron router-port-list stacki-router | grep -q 192.168
      if [ $? != 0 ]; then
         echo "Failed to create a virtual router. Bummer." 
         exit 258
      fi

   else
      echo "Ok"
   fi
}

function download_stacki() {

   iso='stacki-os-3.0-7.x.x86_64.disk1.iso'

   echo -n "Checking for stacki iso: "
   if [ -f $iso ]; then
      echo "Ok"
   else
      echo "Downloading"
      wget -q http://stacki.s3.amazonaws.com/3.0/stacki-os-3.0-7.x.x86_64.disk1.iso
      wget -q http://stacki.s3.amazonaws.com/3.0/md5sum.txt

      # Make sure we have a valid ISO.
      md50=$(grep stacki-os-3.0-7.x.x86_64.disk1.iso md5sum.txt|awk '{print $1}')
      md51=$(md5sum stacki-os-3.0-7.x.x86_64.disk1.iso| awk '{print $1}')
   
      if [ $md50 != $md51 ]; then
         echo "Failed md5sum check. Bummer"
         exit 259
      fi
   fi
}

function unpack_stacki() {

   echo -n "Copying Stacki ISO contents: "
   mkdir mnt
   mount -o loop stacki-os-3.0-7.x.x86_64.disk1.iso mnt/ &> /dev/null

   if [ $? != 0 ]; then
      echo "Failed. Bummer"
      exit 260
   fi

   mkdir bootiso/ &> /dev/null
   rsync -a mnt/ bootiso/

   umount mnt/
   rmdir mnt/
   echo "Ok"
}

function update_frontend_ks() {

   echo -n "Updating Frontend ks.cfg: "
   cat << END > bootiso/ks.cfg
url --url file:///mnt/cdrom
lang en_US
keyboard us
install
%pre
cat > /tmp/site.attrs << 'EOF'
HttpConf:/etc/httpd/conf
HttpConfigDirExt:/etc/httpd/conf.d
HttpRoot:/var/www/html
Info_CertificateCountry:US
Info_CertificateLocality:Solana Beach
Info_CertificateOrganization:StackIQ
Info_CertificateState:California
Info_ClusterContact:
Info_ClusterLatlong:N32.87 W117.22
Info_ClusterName:
Info_ClusterURL:http://$cluster/
Info_FQDN:$cluster
Kickstart_BoxDir:/export/stack
Kickstart_DistroDir:/export/stack
Kickstart_Keyboard:us
Kickstart_Lang:en_US
Kickstart_Langsupport:en_US
Kickstart_PrivateAddress:10.1.1.1
Kickstart_PrivateBroadcast:10.1.1.255
Kickstart_PrivateDNSDomain:$domain
Kickstart_PrivateDNSServers:8.8.8.8
Kickstart_PrivateDjangoRootPassword:sha1$rootpw
Kickstart_PrivateEthernet:
Kickstart_PrivateGateway:10.1.1.1
Kickstart_PrivateHostname:$cluster
Kickstart_PrivateInterface:em0
Kickstart_PrivateKickstartBasedir:distributions
Kickstart_PrivateKickstartCGI:sbin/kickstart.cgi
Kickstart_PrivateKickstartHost:10.1.1.1
Kickstart_PrivateMD5RootPassword:$rootpw
Kickstart_PrivateNTPHost:pool.ntp.org
Kickstart_PrivateNetmask:255.255.255.0
Kickstart_PrivateNetmaskCIDR:24
Kickstart_PrivateNetwork:10.1.1.0
Kickstart_PrivatePortableRootPassword:$rootpw
Kickstart_PrivateRootPassword:$rootpw
Kickstart_PrivateSHARootPassword:$rootpw
Kickstart_PrivateSyslogHost:
Kickstart_PublicAddress:
Kickstart_PublicBroadcast:
Kickstart_PublicDNSDomain:
Kickstart_PublicDNSServers:
Kickstart_PublicEthernet:
Kickstart_PublicGateway:
Kickstart_PublicHostname:
Kickstart_PublicInterface:
Kickstart_PublicKickstartHost:
Kickstart_PublicNTPHost:pool.ntp.org
Kickstart_PublicNetmask:
Kickstart_PublicNetmaskCIDR:
Kickstart_PublicNetwork:
Kickstart_Timezone:America/Denver
RootDir:/root
nukedisks:True
EOF




}

function clean_ssh_known_hosts() {

   fe=$1
   cat /root/.ssh/known_hosts | grep -v $fe > /tmp/known_hosts
   mv /tmp/known_hosts /root/.ssh/known_hosts
   chmod 600 /root/.ssh/known_hosts
}

function repack_iso() {

   echo -n "Creating custom frontend ISO: "
   cd /export/stack_iso/ && \
   mkisofs -V 'Stacki - Disk 1' \
      -b isolinux/isolinux.bin -c isolinux/boot.cat \
      -no-emul-boot -boot-load-size 6 -boot-info-table \
      -r -T -f -input-charset utf-8 -m initrd -m cb-fe -o /var/www/html/iso/stacki/$iso_file . &> /dev/null
   echo "Ok"

   cd $cwd
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

   # Eject ISO if inserted.
   /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $ip get_vm_status |grep image_inserted | grep -iq yes
   if [ $? -eq '0' ]; then
      echo -n "Ejecting a mounted ISO: "
      /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $ip eject_virtual_media device=cdrom &> /dev/null
      echo "Ok"
   fi

   echo -n "Powering down $ip: "
   /usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $ip chassis power off &> /dev/null
   sleep 10
   echo "Ok"

   echo -n "Inserting Virtual Media: "
   /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $ip insert_virtual_media device=CDROM \
      image_url=http://$acid_ip/iso/stacki/$iso_file &> /dev/null
   echo "Ok"

   echo -n "Setting boot priority: "
   /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $ip set_vm_status device=cdrom boot_option=boot_once write_protect=True &> /dev/null
   /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $ip set_one_time_boot device=cdrom &> /dev/null
   /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $ip set_persistent_boot devices=CDROM,NETWORK,HDD,USB,FLOPPY &> /dev/null
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

   start=$(date +"%s")
   echo -n "Waiting for $cluster frontend to install: "
   ssh="ssh -q -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $fe 'hostname' 2>&1 | grep -q $cluster"
   $ssh
   while test $? -gt 0; do
      sleep 5
      $ssh
   done
   clean_ssh_known_hosts $fe

   end=$(date +"%s")
   seconds=$(($end - $start));
   min=$(($seconds / 60))
   echo "Ok (took $min minutes)"
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

   echo -n "Setting pxe boot for $compute: "
   /export/ci/tools/ci/hpilo_cli -l $ilo_user -p $ilo_pass $compute set_persistent_boot devices=NETWORK,HDD,USB,FLOPPY &> /dev/null
   sleep 5
   echo "Ok"

   echo -n "Powering up $compute: "
   /usr/bin/ipmitool -I lanplus -U $ilo_user -P $ilo_pass -H $compute chassis power on &> /dev/null
   echo "Ok"
}

function start_up() {

   # check_os_creds
   # install_centos
   # create_networks
   # create_virtual_router
   download_stacki
   unpack_stacki
}


while [[ $# < 1 ]]; do
   echo ""
   echo "  ./$0 [-c|--create] [-d|--destroy]"
   echo ""
   exit
done

while [[ $# > 0 ]]
do
action="$1"

case $action in
    -d|--destroy)
    DESTROY="yes"
    shift # Completely destory everything.
    ;;
    -c|--create)
    STARTUP="yes"
    shift # Start up the whole virtual cluster.
    ;;


    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

if [ "$DESTROY" == 'yes' ]; then
   while true; do
       echo ""
       read -p "Do you wish to destroy the current install? [y/n]: " yn
       case $yn in
           [Yy]* ) clean_up; exit;;
           [Nn]* ) exit;;
           * ) echo "Please answer yes or no.";;
       esac
   done
fi

if [ "$STARTUP" == 'yes' ]; then
   start_up
   exit
fi


