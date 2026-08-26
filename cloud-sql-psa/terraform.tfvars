project-id = "winter-alliance-357101"
regions = [ "us-central1", "asia-southeast1" ]
apis = [
  "compute.googleapis.com",
  "servicenetworking.googleapis.com",
  "sqladmin.googleapis.com"
]
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-hub"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "hubsub-usc1"
                cidr_block = "10.10.0.0/22"
                region = "us-central1"
            }
        ]
    },
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-isolated"
        delete_default_route    = false
        subnets                 =  [
           {
                subnet_name = "isolated-usc1"
                cidr_block = "10.20.0.0/22"
                region = "us-central1"
            }
        ]
    },
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-onprem"
        delete_default_route    = false
        subnets                 =  [
           {
                subnet_name = "onprem-usc1"
                cidr_block = "10.20.0.0/22"
                region = "us-central1"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-int-hub",
        network  = "vpc-hub",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        project-id = "mhanline-playpen002"
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            },
            {
                protocol = "UDP"
            },
            {
                protocol = "ICMP"
            }
        ]
    },
    {
        id = "90002",
        name = "rfc1918-in-int-isolated",
        network  = "vpc-isolated",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        project-id = "mhanline-playpen002"
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            },
            {
                protocol = "UDP"
            },
            {
                protocol = "ICMP"
            }
        ]
    },
    {
        id = "90003",
        name = "rfc1918-in-int-onprem",
        network  = "vpc-onprem",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        project-id = "mhanline-playpen002"
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            },
            {
                protocol = "UDP"
            },
            {
                protocol = "ICMP"
            }
        ]
    },
    {
        id = "90004",
        name = "iap-allow-onprem",
        network  = "vpc-hub",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1004,
        project-id = "mhanline-playpen002"
        source_list = [ "iap-forwarders" ]
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    },
    {
        id = "90005",
        name = "iap-allow-isolated",
        network  = "vpc-isolated",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1005,
        project-id = "mhanline-playpen002"
        source_list = [ "iap-forwarders" ]
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    },
    {
        id = "90006",
        name = "iap-allow-onprem",
        network  = "vpc-onprem",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1006,
        project-id = "mhanline-playpen002"
        source_list = [ "iap-forwarders" ]
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    }
]