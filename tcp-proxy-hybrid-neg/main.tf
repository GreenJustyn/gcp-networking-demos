terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.32"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.32"
    }
  }
}

provider "google" {
 project     = var.project-id
}

provider "google-beta" {
 project     = var.project-id
}

data "google_compute_zones" "region-availability" {
    for_each    = toset(var.regions)
    region  = each.value
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}

resource "random_shuffle" "gcp-zones" {
    for_each        = { for region in data.google_compute_zones.region-availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
    #result_count    = 2
}

resource "random_id" "id" {
	  byte_length = 2
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "${local.suffix_nodash}-cwd" = path.cwd
  }
}

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

module "vpn_ha-1" {
  source  = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version = "~> 2.3.1"
  project_id  = var.project-id
  region  = var.regions[0]
  network         = module.google-infra-vpc.vpcs["tcp-proxy-hybrid-consumer"].self_link
  name            = "consumer-producer"
  peer_gcp_gateway = module.vpn_ha-2.self_link
  router_asn = 64514
  tunnels = {
    remote-0 = {
      bgp_peer = {
        address = "169.254.1.1"
        asn     = 64513
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.1.2/30"
      ike_version       = 2
      vpn_gateway_interface = 0
      peer_external_gateway_interface = null
      shared_secret     = "A32bracadabrA"
    }
    remote-1 = {
      bgp_peer = {
        address = "169.254.2.1"
        asn     = 64513
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.2.2/30"
      ike_version       = 2
      vpn_gateway_interface = 1
      peer_external_gateway_interface = null
      shared_secret     = "A32bracadabrA"
    }
  }
}

module "vpn_ha-2" {
  source  = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version = "~> 2.3.1"
  project_id  = var.project-id
  region  = var.regions[0]
  network         = module.google-infra-vpc.vpcs["tcp-proxy-hybrid-producer"].self_link
  name            = "producer-consumer"
  router_asn = 64513
  peer_gcp_gateway = module.vpn_ha-1.self_link
  tunnels = {
    remote-0 = {
      bgp_peer = {
        address = "169.254.1.2"
        asn     = 64514
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.1.1/30"
      ike_version       = 2
      vpn_gateway_interface = 0
      peer_external_gateway_interface = null
      shared_secret     = "A32bracadabrA"
    }
    remote-1 = {
      bgp_peer = {
        address = "169.254.2.2"
        asn     = 64514
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.2.1/30"
      ike_version       = 2
      vpn_gateway_interface = 1
      peer_external_gateway_interface = null
      shared_secret     = "A32bracadabrA"
    }
  }
}

resource "google_compute_address" "ilb-reservation" {
  name         = "ilb-reservation-${random_id.id.hex}"
  subnetwork   = module.google-infra-vpc.subnets["consumer-sub-sin"].self_link
  address_type = "INTERNAL"
  address      = cidrhost(module.google-infra-vpc.subnets["consumer-sub-sin"].ip_cidr_range,100)
  region       = var.regions[0]
}

resource "google_compute_network_endpoint_group" "hybrid-neg" {
  name                  = "hybrid-neg-${random_id.id.hex}"
  network               = module.google-infra-vpc.vpcs["tcp-proxy-hybrid-consumer"].self_link
  default_port          = "80"
  zone                  = random_shuffle.gcp-zones[var.regions[0]].result[0]
  network_endpoint_type = "NON_GCP_PRIVATE_IP_PORT"
}

resource "google_compute_network_endpoint" "hybrid-endpoint" {
  network_endpoint_group    = google_compute_network_endpoint_group.hybrid-neg.name
  port                      = google_compute_network_endpoint_group.hybrid-neg.default_port
  zone                      = random_shuffle.gcp-zones[var.regions[0]].result[0]
  ip_address                = google_compute_address.testvm03-reservation.address
}

resource "google_compute_region_health_check" "ilb-hc" {
    check_interval_sec      = 10
    unhealthy_threshold     = 3
    name                    = "hc-${random_id.id.hex}"
    region                  = var.regions[0]
    tcp_health_check {
        port_specification  = "USE_SERVING_PORT"
    }
    log_config {
        enable              = true
    }
}

resource "google_compute_region_backend_service" "tcp-proxy-bs" {
    name                              = "backend-svc-int1-${random_id.id.hex}"
    load_balancing_scheme             = "INTERNAL_MANAGED"
    protocol                          = "TCP"
    region                            = var.regions[0]
    health_checks                     = [google_compute_region_health_check.ilb-hc.self_link]
    #network                           = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    backend {
        group = google_compute_network_endpoint_group.hybrid-neg.self_link
        balancing_mode = "CONNECTION"
        max_connections = 500
        capacity_scaler = 1.0
    }
}

resource "google_compute_region_target_tcp_proxy" "ilb-target-proxy" {
  name            = "ilb-target-proxy-${random_id.id.hex}"
  region          = var.regions[0]
  backend_service = google_compute_region_backend_service.tcp-proxy-bs.id
}

resource "google_compute_forwarding_rule" "l4-proxy-fr" {
    name                    = "fwdrule-int-syd-${random_id.id.hex}"
    network                 = module.google-infra-vpc.vpcs["tcp-proxy-hybrid-consumer"].self_link
    subnetwork              = module.google-infra-vpc.subnets["consumer-sub-sin"].self_link
    ip_address              = google_compute_address.ilb-reservation.address
    load_balancing_scheme   = "INTERNAL_MANAGED"
    ip_protocol             = "TCP"
    port_range              = "80"
    region                  = var.regions[0]
    target                  = google_compute_region_target_tcp_proxy.ilb-target-proxy.id
}


/*
# Internal network ILB
resource "google_compute_forwarding_rule" "ilb-rule-internal-syd" {
    name                    = "fwdrule-int-syd-${random_id.id.hex}"
    network                 = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    subnetwork              = module.google-infra-vpc.subnets["vpc-ilb-syd"].self_link
    ip_address              = var.ip_address_internal1
    all_ports               = true
    load_balancing_scheme   = "INTERNAL"
    ip_protocol             = "TCP"
    region                  = var.regions[0]
    allow_global_access     = true
    backend_service         = google_compute_region_backend_service.backend-vpc-internal1.self_link
}
resource "google_compute_forwarding_rule" "ilb-rule-internal-mel" {
    name                    = "fwdrule-int-mel-${random_id.id.hex}"
    network                 = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    subnetwork              = module.google-infra-vpc.subnets["vpc-ilb-mel"].self_link
    ip_address              = var.ip_address_internal2
    all_ports               = true
    load_balancing_scheme   = "INTERNAL"
    ip_protocol             = "TCP"
    region                  = var.regions[1]
    allow_global_access     = true
    backend_service         = google_compute_region_backend_service.backend-vpc-internal2.self_link
}

resource "google_compute_region_backend_service" "backend-vpc-internal2" {
    name                              = "backend-svc-int2-${random_id.id.hex}"
    load_balancing_scheme             = "INTERNAL"
    protocol                          = "TCP"
    region                            = var.regions[1]
    health_checks                     = [google_compute_health_check.https.self_link]
    connection_draining_timeout_sec   = 10
    network                           = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    backend {
        group = google_compute_region_instance_group_manager.gw_ig_manager2.instance_group
    }
}


resource "google_compute_region_instance_group_manager" "gw_ig_manager1" {
    name                = "gw-ig-syd${random_id.id.hex}"
    base_instance_name  = "gw-ig-syd"
    region              = var.regions[0]
    target_size         = "1"
    version {
        instance_template = google_compute_instance_template.ilb_template.id
    }
    named_port {
        name = "https"
        port = 443
    }
    auto_healing_policies {
        health_check      = google_compute_health_check.https.id
        initial_delay_sec = 30
    }
    update_policy {
        type                            = "PROACTIVE"
        minimal_action                  = "REPLACE"
        most_disruptive_allowed_action  = "REPLACE"
        max_surge_fixed                 = 0
        max_unavailable_fixed           = length(data.google_compute_zones.region-availability[var.regions[0]].names)
    }
}
resource "google_compute_region_instance_group_manager" "gw_ig_manager2" {
    name                = "gw-ig-mel${random_id.id.hex}"
    base_instance_name  = "gw-ig-mel"
    region              = var.regions[1]
    target_size         = "1"
    version {
        instance_template = google_compute_instance_template.ilb_template_mel.id
    }
    named_port {
        name = "https"
        port = 443
    }
    auto_healing_policies {
        health_check      = google_compute_health_check.https.id
        initial_delay_sec = 30
    }
    update_policy {
        type                            = "PROACTIVE"
        minimal_action                  = "REPLACE"
        most_disruptive_allowed_action  = "REPLACE"
        max_surge_fixed                 = 0
        max_unavailable_fixed           = length(data.google_compute_zones.region-availability[var.regions[1]].names)
    }
}

resource "google_compute_instance_template" "ilb_template" {
    name_prefix     = "ilb-tpl-syd${random_id.id.hex}"
    machine_type = "e2-standard-2"
    region       = var.regions[0]
    lifecycle {
        create_before_destroy = true
        ignore_changes = [disk[0].source_image]
    }
    can_ip_forward = true
      metadata = {
        startup-script = "${file("ilb-debian10.sh")}"
    }
    tags = ["allow-hc-${random_id.id.hex}", "allow-ssh-${random_id.id.hex}", "igw-${random_id.id.hex}"]
    disk {
        source_image = data.google_compute_image.debian-image.self_link
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["vpc-ilb-syd"].self_link
        access_config { }
    }
}

resource "google_compute_instance_template" "ilb_template_mel" {
    name_prefix     = "ilb-tpl-mel-${random_id.id.hex}"
    machine_type = "e2-standard-2"
    region       = var.regions[1]
    lifecycle {
        create_before_destroy = true
        ignore_changes = [disk[0].source_image]
    }
    can_ip_forward = true
      metadata = {
        startup-script = "${file("ilb-debian10.sh")}"
    }
    tags = ["allow-hc-${random_id.id.hex}", "allow-ssh-${random_id.id.hex}", "igw-${random_id.id.hex}"]
    disk {
        source_image = data.google_compute_image.debian-image.self_link
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["vpc-ilb-mel"].self_link
        access_config { }
    }
}

resource "google_compute_route" "route-ilb-internal-syd" {
    name                = "default-syd-${random_id.id.hex}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    next_hop_ilb        = google_compute_forwarding_rule.ilb-rule-internal-syd.ip_address
    priority            = "600"
}

resource "google_compute_route" "route-ilb-internal-mel" {
    name                = "default-mel-${random_id.id.hex}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    next_hop_ilb        = google_compute_forwarding_rule.ilb-rule-internal-mel.ip_address
    priority            = "500"
}

resource "google_compute_route" "route-igw-tag" {
    name                = "default-tag-${random_id.id.hex}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    next_hop_gateway    = "default-internet-gateway"
    priority            = "10"
    tags                = ["igw-${random_id.id.hex}"]
}
*/

resource "google_compute_instance" "testvm01" {
    name         = "testvm-consumer-sin-${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[0]
    metadata = {
        startup-script = "${file("debian-client.sh")}"
    }
    tags = ["allow-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["consumer-sub-sin"].self_link
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
}

resource "google_compute_address" "testvm02-reservation" {
  name         = "testvm-reservation${local.suffix}"
  subnetwork   = module.google-infra-vpc.subnets["producer-sub-sin-pupi"].self_link
  address_type = "INTERNAL"
  address      = cidrhost(module.google-infra-vpc.subnets["producer-sub-sin-pupi"].ip_cidr_range,100)
  region       = var.regions[0]
}

resource "google_compute_address" "testvm03-reservation" {
  name         = "testvm-reservation3${local.suffix}"
  subnetwork   = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
  address_type = "INTERNAL"
  address      = cidrhost(module.google-infra-vpc.subnets["producer-sub-sin"].ip_cidr_range,100)
  region       = var.regions[0]
}

resource "google_compute_instance" "testvm02" {
    name         = "testvm-producer-sin${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[1]
    metadata = {
        startup-script = "${file("debian-client.sh")}"
    }
    tags = ["allow-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork  = module.google-infra-vpc.subnets["producer-sub-sin-pupi"].self_link
        network_ip  = google_compute_address.testvm02-reservation.address
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
}

resource "google_compute_instance" "testvm03-producer" {
    name         = "testvm-producer-sin2${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[1]
    metadata = {
        startup-script = "${file("debian-client.sh")}"
    }
    tags = ["allow-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork  = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
        network_ip  = google_compute_address.testvm03-reservation.address
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
}