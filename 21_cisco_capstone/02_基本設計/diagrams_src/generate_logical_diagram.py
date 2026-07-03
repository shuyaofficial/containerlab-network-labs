from diagrams import Diagram, Cluster, Edge
from diagrams.generic.network import Router, Switch
from diagrams.onprem.network import Internet
from diagrams.onprem.client import Client

with Diagram("ネットワーク論理構成図", show=False, filename="network_logical_topology", direction="TB"):
    isp = Internet("ISP")

    with Cluster("本社 BGP AS 65001"):
        with Cluster("OSPF Area 0"):
            hq_edge1 = Router("HQ-Edge1\n200.0.1.1")
            hq_edge2 = Router("HQ-Edge2\n200.0.2.1")
            hq_core1 = Switch("HQ-Core1\nActive")
            hq_core2 = Switch("HQ-Core2\nStandby")
            
            hq_edge1 - hq_core1
            hq_edge1 - hq_core2
            hq_edge2 - hq_core1
            hq_edge2 - hq_core2
            hq_core1 - hq_core2
            
        with Cluster("VLAN 10 営業部"):
            vip = Switch("HSRP 仮想IP\n10.1.10.254")
            hq_pc = Client("Sales PC\n10.1.10.100")
            
            hq_core1 >> Edge(style="dotted") >> vip
            hq_core2 >> Edge(style="dotted") >> vip
            vip - hq_pc

    with Cluster("支社ネットワーク"):
        br_edge = Router("BR-Edge\n200.0.3.1")
        
        with Cluster("VLAN 40 支社LAN"):
            br_pc = Client("Branch PC\n10.2.40.100")
            br_edge - br_pc

    isp >> Edge(label="eBGP") >> hq_edge1
    isp >> Edge(label="eBGP") >> hq_edge2
    isp - br_edge
    
    hq_edge1 >> Edge(label="IPsec VPN トンネル", style="dashed", color="firebrick") >> br_edge
