terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.12"
    }
  }
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

provider "google" {
 project     = var.project-id
}

data "google_compute_zones" "region-availability" {
    for_each    = toset(var.regions)
    region      = each.value
}

data "google_compute_image" "debian-image" {
    family  = "debian-11"
    project = "debian-cloud"
}

resource "random_shuffle" "gcp-zones" {
    for_each        = { for region in data.google_compute_zones.region-availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
    result_count    = 2
}

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "tf-ilb-regional-route${local.suffix}" = path.cwd
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

# Internal network ILB
resource "google_compute_forwarding_rule" "ilb-rule-internal-syd" {
    name                    = "fwdrule-int-syd${local.suffix}"
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
    name                    = "fwdrule-int-mel${local.suffix}"
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

resource "google_compute_region_backend_service" "backend-vpc-internal1" {
    name                              = "backend-svc-int1${local.suffix}"
    load_balancing_scheme             = "INTERNAL"
    protocol                          = "TCP"
    region                            = var.regions[0]
    health_checks                     = [google_compute_health_check.https.self_link]
    connection_draining_timeout_sec   = 10
    network                           = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    backend {
        group = google_compute_region_instance_group_manager.gw_ig_manager1.instance_group
        balancing_mode = "CONNECTION"
    }
}

resource "google_compute_region_backend_service" "backend-vpc-internal2" {
    name                              = "backend-svc-int2${local.suffix}"
    load_balancing_scheme             = "INTERNAL"
    protocol                          = "TCP"
    region                            = var.regions[1]
    health_checks                     = [google_compute_health_check.https.self_link]
    connection_draining_timeout_sec   = 10
    network                           = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    backend {
        group = google_compute_region_instance_group_manager.gw_ig_manager2.instance_group
        balancing_mode = "CONNECTION"
    }
}


resource "google_compute_region_instance_group_manager" "gw_ig_manager1" {
    name                = "gw-ig-syd${local.suffix}"
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
    name                = "gw-ig-mel${local.suffix}"
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
    name_prefix     = "ilb-tpl-syd${local.suffix}"
    machine_type = "e2-standard-2"
    region       = var.regions[0]
    lifecycle {
        create_before_destroy = true
        ignore_changes = [disk[0].source_image]
    }
    can_ip_forward = true
      metadata = {
        startup-script = "${file("ilb-debian11.sh")}"
    }
    tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}", "igw${local.suffix}"]
    disk {
        source_image = data.google_compute_image.debian-image.self_link
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["vpc-ilb-syd"].self_link
        access_config { }
    }
}

resource "google_compute_instance_template" "ilb_template_mel" {
    name_prefix     = "ilb-tpl-mel${local.suffix}"
    machine_type = "e2-standard-2"
    region       = var.regions[1]
    lifecycle {
        create_before_destroy = true
        ignore_changes = [disk[0].source_image]
    }
    can_ip_forward = true
      metadata = {
        startup-script = "${file("ilb-debian11.sh")}"
    }
    tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}", "igw${local.suffix}"]
    disk {
        source_image = data.google_compute_image.debian-image.self_link
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["vpc-ilb-mel"].self_link
        access_config { }
    }
}

resource "google_compute_route" "route-ilb-internal-syd" {
    name                = "default-syd${local.suffix}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    next_hop_ilb        = google_compute_forwarding_rule.ilb-rule-internal-syd.ip_address
    priority            = "600"
}

resource "google_compute_route" "route-ilb-internal-mel" {
    name                = "default-mel${local.suffix}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    next_hop_ilb        = google_compute_forwarding_rule.ilb-rule-internal-mel.ip_address
    priority            = "500"
}

resource "google_compute_route" "route-igw-tag" {
    name                = "default-tag${local.suffix}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-ilb-regional"].self_link
    next_hop_gateway    = "default-internet-gateway"
    priority            = "10"
    tags                = ["igw${local.suffix}"]
}

resource "google_compute_health_check" "https" {
    check_interval_sec  = 10
    unhealthy_threshold = 3
    name    = "hc${local.suffix}"
    https_health_check {
        port                = "443"
        host                = "dns.google"
        port_specification  = "USE_FIXED_PORT"
    }
    log_config {
        enable = true
    }
}

resource "google_compute_instance" "testvm01" {
    name         = "testvm-syd${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[0]
    metadata = {
        startup-script = "${file("debian-11-client.sh")}"
    }
    tags = ["allow-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["vpc-ilb-syd"].self_link
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
    depends_on = [ google_dns_response_policy_rule.packagemanager-com, google_compute_global_forwarding_rule.apis-forwarding-rule ]
}

resource "google_compute_instance" "testvm02" {
    name         = "testvm-mel${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[1]].result[0]
    metadata = {
        startup-script = "${file("debian-11-client.sh")}"
    }
    tags = ["allow-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["vpc-ilb-mel"].self_link
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
    depends_on = [ google_dns_response_policy_rule.packagemanager-com, google_compute_global_forwarding_rule.apis-forwarding-rule ]
}

#
# Extra for adding apt repo to work with the default route removed
#

resource "google_compute_global_address" "psc-ip" {
  for_each      = { for address in var.psc_ips : address.name => address }
  name          = "${each.key}${local.suffix}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  address       = each.value.address
}

resource "google_compute_global_forwarding_rule" "apis-forwarding-rule" {
  for_each              = { for fwdrule in var.psc_ips : fwdrule.name => fwdrule }
  name                  = "${each.key}${local.suffix_nodash}"
  target                = "all-apis"
  network               = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  ip_address            = google_compute_global_address.psc-ip["${each.key}"].id
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis-com" {
    provider = google
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-ilb-regional"].id
    }
}

resource "google_dns_response_policy_rule" "googleapis-com" {
    provider = google
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    rule_name       = "googleapis-com-rule"
    dns_name        = "*.googleapis.com."

  local_data {
    local_datas {
      name    = "*.googleapis.com."
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc-ip["psc"].address]
    }
  }  
}
resource "google_dns_response_policy_rule" "packagemanager-com" {
    provider = google
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    rule_name       = "packagamanager-rule"
    dns_name        = "packages.cloud.google.com."

  local_data {
    local_datas {
      name    = "packages.cloud.google.com."
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc-ip["psc"].address]
    }
  }  

}