provider "google" {
 project     = var.project-id
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

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    project-id  = var.project-id
    #version     = "1.0.0"
    vms         = var.virtual_machines
    namesuffix  = random_id.id.hex
    depends_on = [ module.google-infra-vpc ]
}

/*

resource "google_compute_instance" "instance01" {
  name         = "inst-${random_id.id.hex}-01"
  machine_type = "n1-standard-4"
  zone         = var.zone1
  can_ip_forward = true
  metadata = {
    startup-script = "${file("ilb-multinic-debian9.sh")}"
    serial-port-enable = true
  }
  tags = ["allow-hc-${random_id.id.hex}", "allow-ssh-${random_id.id.hex}"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
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
  network_interface {
    subnetwork = google_compute_subnetwork.mgt-subnet.self_link
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
    startup-script-url = var.startup_script_bucket
    serial-port-enable = true
  }
  tags = ["allow-hc-${random_id.id.hex}", "allow-ssh-${random_id.id.hex}"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
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
  network_interface {
    subnetwork = google_compute_subnetwork.mgt-subnet.self_link
  }
  service_account {
    scopes = ["compute-ro", "storage-ro"]
  }
}
*/
/*


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
*/
