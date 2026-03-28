--Please use this doc if wireguard auto setup fails via the bastion-init.sh script at OCI VM creation time--

To set up WireGuard manually on the OCI VM:

sudo apt-get update -y
sudo apt-get install -y wireguard wireguard-tools


# Generate keys
sudo mkdir -p /etc/wireguard

wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key   #Note the public key generated here. To be used in the GCP VMs' /etc/wireguard/wg0.conf file

sudo chmod 600 /etc/wireguard/server_private.key


# Create wg0.conf
PRIVATE_KEY=$(sudo cat /etc/wireguard/server_private.key)

sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.10.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

[Peer]
# core-5g
PublicKey = <core-5g-wg-public-key>
AllowedIPs = 10.10.0.3/32

[Peer]
# ueransim
PublicKey = <ueransim-wg-public-key>
AllowedIPs = 10.10.0.4/32
EOF"




sudo chmod 600 /etc/wireguard/wg0.conf

sudo systemctl enable wg-quick@wg0

sudo wg-quick up wg0

sudo wg show

# If sudo wg show is not populating packets, especially  after adding a new peer, you can restart wg
sudo wq-quick down wg0 
sudo wq-quick up wg0 




===For Core-5g VM===

sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(sudo cat /etc/wireguard/private.key)
Address = 10.10.0.3/24
MTU = 1380

[Peer]
PublicKey = <oci-vm-wg-public-key>
Endpoint = <oci-vm-public-ip>:51820
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF"

sudo systemctl enable wg-quick@wg0
sudo wg-quick up wg0
sudo wg show



===For UERANSIM VM===

sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(sudo cat /etc/wireguard/private.key)
Address = 10.10.0.4/24
MTU = 1380

[Peer]
PublicKey = <oci-vm-wg-public-key>
Endpoint = <oci-vm-public-ip>:51820
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF"

sudo systemctl enable wg-quick@wg0
sudo wg-quick up wg0
sudo wg show

#Connect to OCI Bastion VM: ssh -i <path-to-ociVM-private-key> ubuntu@<oci-public-ip>
#To connect to core-5g VM: ssh -J ubuntu@<ociVM-public-ip> ubuntu@10.10.0.3
#To connect to ueransim VM: ssh -J ubuntu@<ociVM-public-ip> ubuntu@10.10.0.4


===CHECKS===

If "sudo wg show" command does not show transfer in/out Bytes increasing or ping is not successful, there might be a problem with the routing rules on OCI VM at the OS level.

sudo iptables -L INPUT -n --line-numbers | head -20    #Check the rule if there is any REJECT rule that might be taking precedence over WireGuard-UDP-allow.

In the case below, rule 5 is the default OCI REJECT rule blocking WireGuard UDP

ubuntu@..c:~$ sudo iptables -L INPUT -n --line-numbers | head -20
Chain INPUT (policy ACCEPT)
num  target     prot opt source               destination
--   ------     ---  --  -----                -------                  --------------
5    REJECT     all  --  0.0.0.0/0            0.0.0.0/0            reject-with icmp-host-prohibited2:42 PM


sudo iptables -I INPUT 5 -p udp --dport 51820 -j ACCEPT   # Use this to Allow WireGuard's port 51820.
This command takes the place of line 5 above (the Reject rule).

sudo iptables -L INPUT -n --line-numbers | head -10    # Confirm the new wireguard-allow (port 51820) rule now has precedence over the REJECT rule.

