Subscriber provisioning can be done on WebUI.

Keep this running in your laptop:  ssh -i path-to-oci-vm-private-key -L 5000:10.10.0.3:5000 ubuntu@<oci-vm-public-ip>  


Open http://localhost:5000 in your browser

Username/password: admin/free5gc

Accept the defaults for creatiing a new subscriber and click CREATE

Subscriber 2 can be provisioned here as well. The IMSI is the only thing you would need to change. (Make it ...002)

On UERANSIM VM, ensure the gNB process is running before running the ue processes.

For gnb: sudo ./build/nr-gnb -c config/free5gc-gnb.yaml  # To be run in UERANSIM directory
For ue1: sudo ./build/nr-ue -c config/free5gc-ue.yaml   # To be run in a separate terminal UERANSIM directory
For ue2: sudo ./build/nr-ue -c config/free5gc-ue2.yaml  # To be run in a separate terminal UERANSIM directory 