from diagrams import Cluster, Diagram, Edge
from diagrams.generic.network import Router, Firewall, Switch
from diagrams.generic.os import LinuxGeneral
from diagrams.onprem.network import Internet

graph_attr = {
    "fontsize": "24",
    "pad": "1.0",
}

with Diagram("Theme 22: Enterprise Campus LAN Logical Topology", show=False, filename="theme22_logical_topology", graph_attr=graph_attr):

    with Cluster("Internet Simulator"):
        isp = Router("ISP\n(8.8.8.8)")
        internet = Internet("Internet")
        isp - internet

    with Cluster("Branch (OSPF external, 10.2.0.0/16)"):
        br_edge = Router("BR-Edge\n10.2.40.254")
        br_pc = LinuxGeneral("br-pc\n10.2.40.100")
        br_edge - Edge(color="darkturquoise") - br_pc

    with Cluster("OSPF Area 0 (Backbone 10.0.0.0/24)"):
        fgt = Firewall("FGT-Edge\n(FortiGate 7.2)\nWAN: 200.0.1.1")
        core1 = Switch("Core1\nLo: 10.255.0.1")
        core2 = Switch("Core2\nLo: 10.255.0.2")

        fgt - Edge(label="P08", color="darkgreen") - core1
        fgt - Edge(label="P09", color="darkgreen") - core2
        core1 - Edge(label="P01", color="darkgreen") - core2

    with Cluster("OSPF Area 1 (A-Building 10.10.0.0/16)"):
        with Cluster("Distribution Layer"):
            dist_a1 = Switch("Dist-A1 (ABR)\nHSRP Active\nMST Root")
            dist_a2 = Switch("Dist-A2 (ABR)\nHSRP Standby")
            dist_a1 - Edge(label="Po1 Trunk\n& VLAN901", style="dashed", color="darkblue") - dist_a2

        with Cluster("Access Layer / Endpoints"):
            acc_a1 = Switch("Acc-A1")
            acc_a2 = Switch("Acc-A2")
            sales_pc = LinuxGeneral("pc-sales\nVLAN10: 10.10.10.100")
            dev_pc = LinuxGeneral("pc-dev\nVLAN20: 10.10.20.100")

            dist_a1 - Edge(color="blue") - acc_a1
            dist_a2 - Edge(color="blue") - acc_a1
            dist_a1 - Edge(color="blue") - acc_a2
            dist_a2 - Edge(color="blue") - acc_a2

            acc_a1 - Edge(color="darkturquoise") - sales_pc
            acc_a2 - Edge(color="darkturquoise") - dev_pc

    with Cluster("OSPF Area 2 (B-Building 10.20.0.0/16)"):
        with Cluster("Distribution Layer "):
            dist_b1 = Switch("Dist-B1 (ABR)")

        with Cluster("Access Layer / Endpoints "):
            acc_b1 = Switch("Acc-B1")
            srv_file = LinuxGeneral("srv-file\nVLAN30: 10.20.30.10")
            srv_portal = LinuxGeneral("srv-portal\nVLAN30: 10.20.30.20")

            dist_b1 - Edge(label="Po1 Trunk", color="blue") - acc_b1
            acc_b1 - Edge(color="darkturquoise") - srv_file
            acc_b1 - Edge(color="darkturquoise") - srv_portal

    # Inter-Area links
    core1 - Edge(label="P02", color="darkgreen") - dist_a1
    core1 - Edge(label="P03", color="darkgreen") - dist_a2
    core2 - Edge(label="P04", color="darkgreen") - dist_a1
    core2 - Edge(label="P05", color="darkgreen") - dist_a2

    core1 - Edge(label="P06", color="darkgreen") - dist_b1
    core2 - Edge(label="P07", color="darkgreen") - dist_b1

    # External links
    isp - Edge(label="WAN 200.0.1.0/24", color="orange") - fgt
    isp - Edge(label="WAN 200.0.3.0/24", color="orange") - br_edge

    # IPsec VPN tunnel
    fgt - Edge(label="IPsec VTI (IKEv2)\n172.16.40.0/30", color="deeppink", style="dashed", penwidth="3.0") - br_edge

