variable "project-id" {
    type = string
}
variable "region" {
  type = string
}
variable "zone1" {
  type = string
}
variable "zone2" {
  type = string
}
variable "name" {
  type = string
}
variable "ip_address_internal" {
  type = string
}
variable "ip_address_external" {
  type = string
}
variable "vpcs" {
}

variable "fw_rules" {
}

provider "google" {
 project     = var.project-id
 region      = var.region
}

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "${random_id.id.hex}-cwd" = path.cwd
  }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    #version     = "1.0.0"
    vpcs        = var.vpcs
    namesuffix  = random_id.id.hex
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    #version     = "1.0.0"
    fw_rules    = var.fw_rules
    namesuffix  = random_id.id.hex
    depends_on = [ module.google-infra-vpc ]
}

# Internal network ILB
resource "google_compute_forwarding_rule" "ilb-rule-internal" {
  name                  = "fwdrule-int-${random_id.id.hex}"
  network               = google_compute_network.vpc-internal.self_link
  subnetwork            = google_compute_subnetwork.internal-subnet.self_link
  ip_address            = var.ip_address_internal
  all_ports             = true
  load_balancing_scheme = "INTERNAL"
  region                = var.region
  backend_service       = google_compute_region_backend_service.backend-vpc-internal.self_link
}

resource "google_compute_region_backend_service" "backend-vpc-internal" {
  name                            = "backend-svc-int-${random_id.id.hex}"
  load_balancing_scheme           = "INTERNAL"
  region                          = var.region
  health_checks                   = [google_compute_health_check.http.self_link]
  connection_draining_timeout_sec = 10
  session_affinity                = "CLIENT_IP"
  network                         = google_compute_network.vpc-internal.self_link
  backend {
    group = google_compute_instance_group.ig-zone1.self_link
  }
  backend {
    group = google_compute_instance_group.ig-zone2.self_link
  }
}

resource "google_compute_route" "route-ilb-internal" {
  name         = "ilbroute-int-${random_id.id.hex}"
  dest_range   = "10.229.64.0/24"
  network      = google_compute_network.vpc-internal.self_link
  next_hop_ilb = google_compute_forwarding_rule.ilb-rule-internal.id
  priority     = 150
}

# External network ILB
resource "google_compute_forwarding_rule" "ilb-rule-external" {
  name                  = "fwdrule-ext-${random_id.id.hex}"
  network               = google_compute_network.vpc-external.self_link
  subnetwork            = google_compute_subnetwork.external-subnet.self_link
  ip_address            = var.ip_address_external
  all_ports             = true
  load_balancing_scheme = "INTERNAL"
  region                = var.region
  backend_service       = google_compute_region_backend_service.backend-vpc-external.self_link
}

resource "google_compute_region_backend_service" "backend-vpc-external" {
  name                            = "backend-svc-ext-${random_id.id.hex}"
  load_balancing_scheme           = "INTERNAL"
  region                          = var.region
  health_checks                   = [google_compute_health_check.http.self_link]
  connection_draining_timeout_sec = 10
  session_affinity                = "CLIENT_IP"
  network                         = google_compute_network.vpc-external.self_link
  backend {
    group = google_compute_instance_group.ig-zone1.self_link
  }
  backend {
    group = google_compute_instance_group.ig-zone2.self_link
  }
}

resource "google_compute_route" "route-ilb-external" {
  name         = "ilbroute-ext-${random_id.id.hex}"
  dest_range   = "10.229.65.0/24"
  network      = google_compute_network.vpc-external.self_link
  next_hop_ilb = google_compute_forwarding_rule.ilb-rule-external.id
  priority     = 150
}

resource "google_compute_instance_group" "ig-zone1" {
  name = "ig-${random_id.id.hex}-${var.zone1}"
  description = "Instance Group for VMs in Zone 1"
  zone = var.zone1
  instances = [
    google_compute_instance.instance01.self_link
  ]
}

resource "google_compute_instance_group" "ig-zone2" {
  name = "ig-${random_id.id.hex}-${var.zone2}"
  description = "Instance Group for VMs in Zone 2"
  zone = var.zone2
  instances = [
    google_compute_instance.instance02.self_link
  ]
}

resource "google_compute_health_check" "http" {
  name    = "hc-${random_id.id.hex}"
  http_health_check {
    port = "80"
  }
}

resource "google_compute_subnetwork" "external-subnet" {
  name          = "ilbtest-${random_id.id.hex}-ext"
  ip_cidr_range = "10.229.64.0/24"
  region        = var.region
  network       = google_compute_network.vpc-external.self_link
}

resource "google_compute_subnetwork" "internal-subnet" {
  name          = "ilbtest-${random_id.id.hex}-int"
  ip_cidr_range = "10.229.65.0/24"
  region        = var.region
  network       = google_compute_network.vpc-internal.self_link
}

resource "google_compute_network" "vpc-internal" {
  name                    = "ilbtest-${random_id.id.hex}-int"
  auto_create_subnetworks = false
}
resource "google_compute_network" "vpc-external" {
  name                    = "ilbtest-${random_id.id.hex}-ext"
  auto_create_subnetworks = false
}

resource "google_compute_instance" "instance01" {
  name         = "inst-${random_id.id.hex}-01"
  machine_type = "n1-standard-4"
  zone         = var.zone1
  can_ip_forward = true
  metadata = {
    startup-script = "${file("ilb-multinic-debian10.sh")}"
    serial-port-enable = true
  }
  tags = ["allow-hc-${random_id.id.hex}", "allow-ssh-${random_id.id.hex}"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.external-subnet.self_link
    access_config {
      // Ephemeral IP
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.internal-subnet.self_link
  }
  service_account {
    scopes = ["compute-ro", "storage-ro"]
  }
}

resource "google_compute_instance" "instance02" {
  name         = "inst-${random_id.id.hex}-02"
  machine_type = "n1-standard-4"
  zone         = var.zone2
  can_ip_forward = true
  metadata = {
    startup-script = "${file("ilb-multinic-debian10.sh")}"
    serial-port-enable = true
  }
  tags = ["allow-hc-${random_id.id.hex}", "allow-ssh-${random_id.id.hex}"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.external-subnet.self_link
    access_config {
      // Ephemeral IP
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.internal-subnet.self_link
  }
  service_account {
    scopes = ["compute-ro", "storage-ro"]
  }
}

resource "google_compute_instance" "testvm01" {
  name         = "testvm-${random_id.id.hex}-01"
  machine_type = "e2-micro"
  zone         = var.zone1
  metadata = {
    serial-port-enable = true
  }
  tags = ["allow-ssh-${random_id.id.hex}"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.internal-subnet.self_link
    access_config {
      // Ephemeral IP
    }
  }
  service_account {
    scopes = ["compute-ro", "storage-ro"]
  }
}

resource "google_compute_instance" "testvm02" {
  name         = "testvm-${random_id.id.hex}-02"
  machine_type = "e2-micro"
  zone         = var.zone1
  metadata = {
    serial-port-enable = true
  }
  tags = ["allow-ssh-${random_id.id.hex}"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.external-subnet.self_link
    access_config {
      // Ephemeral IP
    }
  }
  service_account {
    scopes = ["compute-ro", "storage-ro"]
  }
}


resource "google_compute_firewall" "health_checks" {
  name    = "fw-allow-hc-${random_id.id.hex}"
  network = google_compute_network.vpc-internal.self_link
  allow {
    protocol = "tcp"
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = [
      "allow-hc-${random_id.id.hex}"
    ]
}

resource "google_compute_firewall" "health_checks-ext" {
  name    = "fw-allow-hc-ext-${random_id.id.hex}"
  network = google_compute_network.vpc-external.self_link
  allow {
    protocol = "tcp"
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = [
      "allow-hc-${random_id.id.hex}"
    ]
}