
==Ping path to the Internet from UE1==

UE1 (uesimtun0 10.60.0.1)
    │
    │ TUN interface — kernel routes packet into UERANSIM
    ▼
nr-ue process (UERANSIM)
    │
    │ Encapsulates ICMP in NAS/SDAP/PDCP/RLC/MAC (radio stack simulation)
    ▼
nr-gnb process (UERANSIM)
    │
    │ Encapsulates in GTP-U (adds TEID header)
    │ UDP port 2152
    ▼
ens4 (10.0.2.2) — ueransim VM
    │
    │ GCP internal network
    ▼
ens4 (10.0.2.3) — core-5g VM
    │
    │ UPF receives GTP-U packet
    │ gtp5g kernel module decapsulates
    ▼
upfgtp interface
    │
    │ UPF applies PDR/FAR rules (PFCP from SMF)
    │ NAT MASQUERADE (iptables, ens4)
    ▼
ens4 (10.0.2.3) — exits as core-5g public IP
    │
    │ Internet
    ▼
8.8.8.8

 >> Reply follows exact reverse path <<