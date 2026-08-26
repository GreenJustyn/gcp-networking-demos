provider "google" {
  #version     = "~> 3.28.0"
  project     = var.project-id
  region      = var.region-1
}
provider "google-beta" {
  project     = var.project-id
  region      = var.region-1
}

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

module "vpc-hub" {
    source  = "terraform-google-modules/network/google"
    #version = "~> 2.4"
    project_id = var.project-id
    network_name = "vpc-hub"
    routing_mode = "GLOBAL"

    subnets = [
        {
            subnet_name           = "hubsub-asia-se1"
            subnet_ip             = "10.10.0.0/22"
            subnet_region         = var.region-1
            subnet_private_access = "true"
        }
    ]
    secondary_ranges = {
        "hubsub-asia-se1" = [
            {
                range_name    = "pod-range"
                ip_cidr_range = "10.10.64.0/18"
            },
            {
                range_name    = "service-range"
                ip_cidr_range = "10.10.128.0/18"
            }
        ]
    }
}
module "vpc-cloudbuild" {
    source  = "terraform-google-modules/network/google"
    #version = "~> 2.4"
    project_id = var.project-id
    network_name = "vpc-cloudbuild"
    routing_mode = "GLOBAL"

    subnets = [
        {
            subnet_name           = "cloudbuildsub-asia-se1"
            subnet_ip             = "10.20.0.0/22"
            subnet_region         = var.region-1
            subnet_private_access = "true"
        }
    ]
}

#resource "google_compute_network_peering" "hub-cloudbuild" {
#  name         = "hub-cloudbuild"
#  network      = module.vpc-hub.network_self_link
#  peer_network = module.vpc-cloudbuild.network_self_link
#}
#resource "google_compute_network_peering" "cloudbuild-hub" {
#  name         = "cloudbuild-hub"
#  network      = module.vpc-cloudbuild.network_self_link
#  peer_network = module.vpc-hub.network_self_link
#}


#VPN

resource "google_compute_ha_vpn_gateway" "hub-gateway" {
  provider = google-beta
  region   = var.region-1
  name     = "hub-vpn1"
  network  = module.vpc-hub.network_self_link
}
resource "google_compute_ha_vpn_gateway" "cloudbuild-gateway" {
  provider = google-beta
  region   = var.region-1
  name     = "cloudbuild-vpn1"
  network  = module.vpc-cloudbuild.network_self_link
}

resource "google_compute_router" "router-hub" {
  provider = google-beta
  name     = "ha-vpn-hub-rtr"
  network  = module.vpc-hub.network_self_link
  bgp {
    asn = 64514
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
    advertised_ip_ranges {
      range = "10.10.192.0/28"
    }
  }
}
resource "google_compute_router" "router-cloudbuild" {
  provider = google-beta
  name     = "ha-vpn-cloudbuild-rtr"
  network  = module.vpc-cloudbuild.network_self_link
  bgp {
    asn = 64515
  }
}

resource "google_compute_vpn_tunnel" "hub-tunnel1" {
  provider              = google-beta
  name                  = "ha-vpn-hub-tun1"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.hub-gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.cloudbuild-gateway.id
  shared_secret         = "lQyrq82T0z"
  router                = google_compute_router.router-hub.id
  vpn_gateway_interface = 0
}
resource "google_compute_vpn_tunnel" "hub-tunnel2" {
  provider              = google-beta
  name                  = "ha-vpn-hub-tun2"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.hub-gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.cloudbuild-gateway.id
  shared_secret         = "vgBE3S7ZAh"
  router                = google_compute_router.router-hub.id
  vpn_gateway_interface = 1
}

resource "google_compute_vpn_tunnel" "cloudbuild-tunnel1" {
  provider              = google-beta
  name                  = "ha-vpn-cloudbuild-tun1"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.cloudbuild-gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub-gateway.id
  shared_secret         = "lQyrq82T0z"
  router                = google_compute_router.router-cloudbuild.id
  vpn_gateway_interface = 0
}
resource "google_compute_vpn_tunnel" "cloudbuild-tunnel2" {
  provider              = google-beta
  name                  = "ha-vpn-cloudbuild-tun2"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.cloudbuild-gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub-gateway.id
  shared_secret         = "vgBE3S7ZAh"
  router                = google_compute_router.router-cloudbuild.id
  vpn_gateway_interface = 1
}

resource "google_compute_router_interface" "router-hub_int1" {
  provider   = google-beta
  name       = "router-hub-int1"
  router     = google_compute_router.router-hub.name
  region     = var.region-1
  ip_range   = "169.254.0.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub-tunnel1.name
}

resource "google_compute_router_peer" "router-hub_peer1" {
  provider                  = google-beta
  name                      = "router-hub-peer1"
  router                    = google_compute_router.router-hub.name
  region                    = var.region-1
  peer_ip_address           = "169.254.0.2"
  peer_asn                  = 64515
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router-hub_int1.name
}

resource "google_compute_router_interface" "router-hub_int2" {
  provider   = google-beta
  name       = "router-hub-int2"
  router     = google_compute_router.router-hub.name
  region     = var.region-1
  ip_range   = "169.254.1.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub-tunnel2.name
}

resource "google_compute_router_peer" "router-hub_peer2" {
  provider                  = google-beta
  name                      = "router1-peer2"
  router                    = google_compute_router.router-hub.name
  region                    = var.region-1
  peer_ip_address           = "169.254.1.2"
  peer_asn                  = 64515
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router-hub_int2.name
}

resource "google_compute_router_interface" "router-cloudbuild_int1" {
  provider   = google-beta
  name       = "router-cloudbuild-int1"
  router     = google_compute_router.router-cloudbuild.name
  region     = var.region-1
  ip_range   = "169.254.0.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.cloudbuild-tunnel1.name
}

resource "google_compute_router_peer" "router-cloudbuild_peer1" {
  provider                  = google-beta
  name                      = "router-cloudbuild-peer1"
  router                    = google_compute_router.router-cloudbuild.name
  region                    = var.region-1
  peer_ip_address           = "169.254.0.1"
  peer_asn                  = 64514
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router-cloudbuild_int1.name
}

resource "google_compute_router_interface" "router-cloudbuild_int2" {
  provider   = google-beta
  name       = "router-cloudbuild-int2"
  router     = google_compute_router.router-cloudbuild.name
  region     = var.region-1
  ip_range   = "169.254.1.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.cloudbuild-tunnel2.name
}

resource "google_compute_router_peer" "router-cloudbuild_peer2" {
  provider                  = google-beta
  name                      = "router-cloudbuild-peer2"
  router                    = google_compute_router.router-cloudbuild.name
  region                    = var.region-1
  peer_ip_address           = "169.254.1.1"
  peer_asn                  = 64514
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router-cloudbuild_int2.name
}

#GKE Private Cluster

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  project_id                 = var.project-id
  name                       = "gke-test-1"
  region                     = var.region-1
  regional                   = true
  network                    = module.vpc-hub.network_name
  subnetwork                 = module.vpc-hub.subnets_names[0]
  ip_range_pods              = "pod-range"
  ip_range_services          = "service-range"
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  network_policy             = false
  enable_private_nodes       = true
  master_ipv4_cidr_block     = "10.10.192.0/28"

  node_pools = [
    {
      name               = "default-node-pool"
      machine_type       = "e2-standard-2"
      min_count          = 1
      max_count          = 3
      local_ssd_count    = 0
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      image_type         = "COS"
      auto_repair        = true
      auto_upgrade       = true
      #service_account    = "project-service-account@<PROJECT ID>.iam.gserviceaccount.com"
      preemptible        = false
      initial_node_count = 1
    },
  ]

  node_pools_oauth_scopes = {
    all = []

    default-node-pool = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_metadata = {
    all = {}

    default-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }
}

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 22
  address       = "10.20.192.0"
  network       = module.vpc-cloudbuild.network_self_link
}

resource "google_service_networking_connection" "foobar" {
  network                 = module.vpc-cloudbuild.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}