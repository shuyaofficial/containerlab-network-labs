from diagrams import Diagram, Cluster, Edge
from diagrams.generic.network import Router, Switch
from diagrams.onprem.network import Internet
from diagrams.onprem.client import Client

with Diagram("ネットワーク物理構成図", show=False, filename="network_physical_topology", direction="TB"):
    isp = Internet("ISP ルーター")

    with Cluster("本社拠点 (Headquarters)"):
        hq_edge1 = Router("HQ-Edge1")
        hq_edge2 = Router("HQ-Edge2")
        
        hq_core1 = Switch("HQ-Core1")
        hq_core2 = Switch("HQ-Core2")
        
        hq_pc = Client("HQ-PC-Sales")
        
        hq_edge1 - Edge(label="eth2 - eth1") - hq_core1
        hq_edge1 - Edge(label="eth3 - eth1") - hq_core2
        hq_edge2 - Edge(label="eth2 - eth2") - hq_core1
        hq_edge2 - Edge(label="eth3 - eth2") - hq_core2
        
        hq_core1 - Edge(label="eth5/6 - eth5/6") - hq_core2
        hq_core1 - Edge(label="eth7 - eth1") - hq_pc

    with Cluster("支社拠点 (Branch)"):
        br_edge = Router("BR-Edge")
        br_pc = Client("BR-PC")
        
        br_edge - Edge(label="eth2 - eth1") - br_pc

    isp - Edge(label="eth1 - eth1") - hq_edge1
    isp - Edge(label="eth2 - eth1") - hq_edge2
    isp - Edge(label="eth3 - eth1") - br_edge
