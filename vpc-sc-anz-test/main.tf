#FYI: You need to add a role to your own account, Service Account Token Creator, to allow it to impersonate the service account.

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    project_ids = toset(flatten([var.protected_project_ids, var.unprotected_project_ids]))
    apis_per_project  = flatten([
        for project in var.protected_project_ids: [
            for api in var.apis: {
                api_name    = api
                project_id  = project
            }
        ]
    ])
    roles_per_project = flatten([
        for project in local.project_ids: [
        for role in var.sa_project_roles: {
            role = role
            project = project
        }
        ]
    ])
}
resource "random_id" "id" {
	byte_length = 3
}

data "google_client_config" "default" {
}

data "google_project" "protected_projects" {
  for_each = toset(var.protected_project_ids)
  project_id  = each.value
}

resource "google_service_account" "vpc_sc_sa" {
    account_id      = "vpc-sc-sa${local.suffix}"
    display_name    = "vpc-sc-service-acct${local.suffix}"
}

data "google_service_account_access_token" "sa" {
    target_service_account  = google_service_account.vpc_sc_sa.email
    lifetime                = "300s"
    scopes                  = [
        "https://www.googleapis.com/auth/cloud-platform",
    ]
}
data "google_compute_image" "debian_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

resource "random_shuffle" "gcp_zones" {
  for_each        = { for region in data.google_compute_zones.region_availability: region.region => region.names }
  input           = [ for zone in each.value : zone ]
  result_count    = 2
}
data "google_compute_zones" "region_availability" {
  provider      = google.impersonation
  depends_on    = [ google_project_iam_member.sa_roles ]
  for_each      = toset([var.region])
  region        = each.value
}

resource "google_project_iam_member" "sa_roles" {
  for_each  = {for item in local.roles_per_project: "${item.role}_${item.project}" => item}
  project   = each.value.project
  role      = each.value.role
  member    = google_service_account.vpc_sc_sa.member
}

provider "google" {
    access_token    = data.google_service_account_access_token.sa.access_token
    project         = var.protected_project_ids[0]
    alias           = "impersonation"
}
provider "google" {
  project     = var.protected_project_ids[0]
}

resource "google_compute_project_metadata" "default" {
    for_each    = toset(var.protected_project_ids)
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "vpc-sc-anz-test${local.suffix}-cwd" = path.cwd
    }
}

resource "google_project_service" "apienable" {
    for_each            = { for item in local.apis_per_project: "${item.api_name}_${item.project_id}" => item }
    project             = each.value.project_id
    service             = each.value.api_name
    disable_on_destroy  = false
    disable_dependent_services  = true
}

resource "google_organization_iam_member" "vpc-sc-member" {
    org_id      = var.parent_id
    role        = "roles/accesscontextmanager.policyAdmin"
    member      = "serviceAccount:${google_service_account.vpc_sc_sa.email}"
}

resource "google_access_context_manager_access_policy" "access-policy" {
    parent        = "organizations/${var.parent_id}"
    #provider      = google.impersonation
    title         = "access context manager access policy for ${local.suffix_nodash}"
}

resource "google_access_context_manager_service_perimeter" "service_perimeter" {
    for_each    = var.vpc_sc_perimeters
    #provider    = google.impersonation
    parent      = "accessPolicies/${google_access_context_manager_access_policy.access-policy.name}"
    name        = "accessPolicies/${google_access_context_manager_access_policy.access-policy.name}/servicePerimeters/${each.key}"
    title       = "${each.key} Restrict APIs"
    status {
        restricted_services = var.protected_apis
        resources           = [ for item in each.value: "projects/${data.google_project.protected_projects[item].number}"]
        vpc_accessible_services {
            enable_restriction = true
            allowed_services   = var.protected_apis
        }
    }
    lifecycle {
        ignore_changes = [status[0]]
    }
    depends_on = [
        google_project_iam_member.sa_roles
    ]
}

resource "google_access_context_manager_service_perimeter_ingress_policy" "ingress_policy_external" {
  #provider      = google.impersonation
  for_each      = var.vpc_sc_perimeters
  perimeter     = "${google_access_context_manager_service_perimeter.service_perimeter[each.key].name}"
  ingress_from {
    identities  = [ "serviceAccount:${google_service_account.vpc_sc_sa.email}" ]
    sources {
      access_level  = "*"
    }
  }
  ingress_to {
    resources = formatlist("projects/%s",values(data.google_project.protected_projects)[*].number)
    operations {
      service_name = "*"
    }
  }
  lifecycle {
        create_before_destroy = true
  }
}

resource "google_access_context_manager_service_perimeter_ingress_policy" "ingress_policy_for_gcp" {
  #provider      = google.impersonation
  for_each      = var.vpc_sc_perimeters
  perimeter     = "${google_access_context_manager_service_perimeter.service_perimeter[each.key].name}"
  ingress_from {
    identities  = [ "serviceAccount:${google_service_account.vpc_sc_sa.email}" ]
    sources {
        #Cloud Shell project
        resource      = "projects/751522334863"
    }
  }
  ingress_to {
        resources = formatlist("projects/%s",values(data.google_project.protected_projects)[*].number)
        operations {
            service_name = "*"
    }
  }
  lifecycle {
        create_before_destroy = true
  }
}

#
# VPC/Subnet/Firewall/VMs
#

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

# DNS #

resource "google_dns_managed_zone" "google-apis" {
    name        = "zone${local.suffix}"
    project     = var.protected_project_ids[0]
    dns_name    = "googleapis.com."
    description = "private zone for Google APIs"
    visibility = "private"
    private_visibility_config {
        networks {
            network_url = module.google-infra-vpc.vpcs["vpc1-in-perim1"].self_link
        }
    }
}

resource "google_dns_record_set" "restricted-google-apis-A-record" {
  name    = "restricted.googleapis.com."
  project = var.protected_project_ids[0]
  type    = "A"
  ttl     = 300
  managed_zone = google_dns_managed_zone.google-apis.name
  rrdatas = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
}

resource "google_dns_record_set" "private-google-apis-A-record" {
  name    = "private.googleapis.com."
  project = var.protected_project_ids[0]
  type    = "A"
  ttl     = 300
  managed_zone = google_dns_managed_zone.google-apis.name
  rrdatas = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
}
/*
resource "google_dns_record_set" "storage_api_cname
" {
  name    = "storage.googleapis.com."
  project = var.protected_project_ids[0]
  type    = "CNAME"
  ttl     = 300
  managed_zone = google_dns_managed_zone.google-apis.name
  rrdatas = ["private.googleapis.com."]
}

resource "google_dns_record_set" "sheets_api_cname" {
  name    = "sheets.googleapis.com."
  project = var.protected_project_ids[0]
  type    = "CNAME"
  ttl     = 300
  managed_zone = google_dns_managed_zone.google-apis.name
  rrdatas = ["private.googleapis.com."]
}
*/
#Storage bucket for testing#

resource "google_storage_bucket" "gcs_bucket" {
    provider      = google.impersonation
    name          = "bugcket${local.suffix}"
    storage_class = "MULTI_REGIONAL"
    location      = "ASIA"
    depends_on = [
        google_access_context_manager_service_perimeter_ingress_policy.ingress_policy_external,
        google_access_context_manager_service_perimeter_ingress_policy.ingress_policy_for_gcp
    ]
}

resource "google_storage_bucket_iam_member" "all_users_viewers" {
    provider      = google.impersonation
    bucket = google_storage_bucket.gcs_bucket.name
    role   = "roles/storage.legacyObjectReader"
    member = "allUsers"
}

resource "google_storage_bucket_object" "file" {
    provider      = google.impersonation
    name   = "test_file.txt"
    source = "./test_file.txt"
    bucket = google_storage_bucket.gcs_bucket.name
}

#Compute Engine VMs
resource "google_compute_instance" "testvms" {
    provider            = google.impersonation
    for_each            = { for vm in var.vms : vm.name => vm }
    project             = each.value.project
    name                = "${each.key}${local.suffix}"
    machine_type        = each.value.size
    zone                = random_shuffle.gcp_zones[each.value.region].result[0]
    metadata            = {
        startup-script      = templatefile("./debian-11-client.sh.tftpl", {})
    }
    allow_stopping_for_update = true
    tags = [ ]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian_image.self_link
        }
    }
    network_interface {
        subnetwork  = module.google-infra-vpc.subnets[each.value.subnet].self_link
        network_ip  = google_compute_address.vm_reservation[each.key].address
        access_config {
            // Ephemeral IP
        }
    }
    service_account {
        scopes = ["cloud-platform"]
    }
    depends_on  = [
        google_project_iam_member.sa_roles,
        google_access_context_manager_service_perimeter_ingress_policy.ingress_policy_external,
        google_access_context_manager_service_perimeter_ingress_policy.ingress_policy_for_gcp
    ]
}
resource "google_compute_address" "vm_reservation" {
    provider      = google.impersonation
    depends_on    = [ 
        google_project_iam_member.sa_roles,
        google_access_context_manager_service_perimeter_ingress_policy.ingress_policy_external,
        google_access_context_manager_service_perimeter_ingress_policy.ingress_policy_for_gcp
    ]
    for_each      = { for vm in var.vms : vm.name => vm }
    project       = each.value.project
    name          = "res-${each.key}${local.suffix}"
    subnetwork    = module.google-infra-vpc.subnets[each.value.subnet].self_link
    address_type  = "INTERNAL"
    address       = cidrhost(module.google-infra-vpc.subnets[each.value.subnet].ip_cidr_range,10)
    region        = each.value.region
}