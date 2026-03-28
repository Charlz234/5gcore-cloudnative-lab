
If gtp5g did not get installed automatically, kindly follow the steps below to install it on Core-5g VM

1. Install Build Dependencies

sudo apt update
sudo apt install -y git gcc g++ cmake autoconf libtool pkg-config libmnl-dev libyaml-dev linux-headers-$(uname -r)

2. Clone and Build v0.9.14 

# Move to your home directory or a workspace
cd ~
# Clone the specific version
git clone -b v0.9.14 https://github.com/free5gc/gtp5g.git
cd gtp5g
# Compile and install
make
sudo make install


3. Verify the Module is Loaded 
After installation, verify that the module is active in the kernel: 

lsmod | grep gtp5g

You should see something like the below:
gtp5g                 <size>  0
udp_tunnel             <size>  3 gtp5g,wireguard,sctp

This means the installation was successful. If the output is empty, kindly verify the actions taken in the steps above

4. Restart your Free5GC Stack
Now that the host kernel supports GTP, you can restart the Docker containers: 


cd ~/free5gc-compose
docker compose down --remove-orphans
docker compose up -d


Other troubleshoting commands:
docker compose ps  # To be run in ~/free5gc-compose directory
docker logs <container name or container id>. E.g., docker logs amf | tail -20
or watch the logs with docker logs --tail 20 -f amf . ctrl + c to stop