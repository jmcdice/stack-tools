# - Missing interfaces on the backend nodes
# - yum repos missing on the FE
# - TFTP FW rules on the FE private network (stack list host firewall)
#   stack repoort host firewall # stack sync config
#   play with the storage configuration stuff
# - Add stacki ISO to the FE

function add_repos() {

   echo -n "Configuring Yum Repos: "
   stack report host yum localhost | stack report script | bash &> /dev/null
   echo "Ok"
}

function install_rpms() {

   echo -n "Installing additional RPM's: "
   yum -y install vim-enhanced tcpdump lsof  &> /dev/null
   echo "Ok"
}

function add_appliances() {

   echo -n "Adding additional appliance types: "
   /opt/stack/bin/stack add appliance compute membership=Compute node=backend
   /opt/stack/bin/stack add appliance vm-manager membership="VM Management Node" node=backend
   /opt/stack/bin/stack set appliance attr compute attr=managed value=true
   /opt/stack/bin/stack set appliance attr vm-manager attr=managed value=true
   echo "Ok"
}

function add_public_network() {

   echo -n "Creating public network: "
   /opt/stack/bin/stack add network public \
        address=172.29.55.0        \
        mask=255.255.255.0                \
        zone=public.cloud-band.com     \
        gateway=172.29.55.1        \
        dns=true pxe=false &> /dev/null

   echo "Ok"
}

function add_computes() {

   echo -n "Adding baremetal computes: "
cat > /root/computes.csv<< 'EOF'
NAME,INTERFACE HOSTNAME,DEFAULT,APPLIANCE,RACK,RANK,IP,MAC,INTERFACE,NETWORK,CHANNEL,OPTIONS,VLAN
vm-manager-0-0,,,vm-manager,1,1,10.1.255.254,10:1f:74:35:86:e8,enp2s0f0,private,,,
compute-0-0,,,compute,1,2,10.1.255.253,10:1f:74:35:96:38,enp2s0f0,private,,,
compute-0-1,,,compute,1,3,10.1.255.252,78:e3:b5:16:5d:00,enp2s0f0,private,,,
compute-0-2,,,compute,1,4,10.1.255.251,10:1f:74:35:56:60,enp2s0f0,private,,,
stacki-poc,,,frontend,0,0,10.1.1.1,10:1f:74:34:4f:b8,enp2s0f0,private,,,
stacki-poc,,True,frontend,0,0,172.29.55.10,10:1f:74:34:4f:b9,enp2s0f2,public,,,
EOF

   stack load hostfile file=computes.csv &> /dev/null
   echo "Ok"

   echo -n "Setting compute Bootaction to install: "
   stack set host boot compute vm-manager action=install
   echo "Ok"
}

function update_ipt() {

   # FIXME: allow pxe/dhcp/tftp on private network
   echo -n "Updating iptables config: "
   systemctl stop iptables.service 
   echo "Ok"
}

add_repos
install_rpms
add_appliances
add_public_network
add_computes
update_ipt
