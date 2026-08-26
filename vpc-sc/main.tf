terraform {
  required_providers {
    google-beta = {
      source      = "hashicorp/google-beta"
      version     = ">= 7.44"
    }
    google = {
      source      = "hashicorp/google"
      version     = ">= 7.44"
    }
  }
}

data "google_project_ancestry" "default" {
  for_each = { for project in local.project_ids: project => null }
  project = each.key
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_underscore = try(var.append_rand, true) == true ? "_${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
  project_ids = toset(flatten([var.protected_project_ids, var.unprotected_project_ids]))
  apis_per_project  = flatten([
    for project in toset(flatten([var.protected_project_ids, var.unprotected_project_ids])): [
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

provider "google" {
  project         = var.protected_project_ids[0]
  billing_project = var.protected_project_ids[0]
}
provider "google-beta" {
  project         = var.protected_project_ids[0]
  billing_project = var.protected_project_ids[0]
}

resource "google_project_service" "apienable" {
  for_each            = { for item in local.apis_per_project: "${item.api_name}_${item.project_id}" => item }
  project             = each.value.project_id
  service             = each.value.api_name
  disable_on_destroy  = false
  disable_dependent_services  = true
}

resource "google_compute_project_metadata" "default" {
  provider  = google.impersonation
  for_each  = local.project_ids
  project   = each.value
  metadata  = {
    enable-oslogin  = "TRUE"
    "tf-created${local.suffix}" = path.cwd
  }
  depends_on = [
    google_project_iam_member.sa_roles,
    google_access_context_manager_service_perimeter.service_perimeter
  ]
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "random_shuffle" "gcp_zones" {
  for_each        = { for region in data.google_compute_zones.region_availability: region.region => region.names }
  input           = [ for zone in each.value : zone ]
  result_count    = 2
}

data "google_compute_zones" "region_availability" {
  project       = var.protected_project_ids[0]
  provider      = google.impersonation
  depends_on    = [ google_project_iam_member.sa_roles ]
  for_each      = toset([var.region])
  region        = each.value
}

data "google_compute_image" "debian_image" {
  family  = "debian-12"
  project = "debian-cloud"
}

################
#IAM & Service Account Setup
resource "google_service_account" "vpc_sc_sa" {
  project         = var.protected_project_ids[0]
  account_id      = "vpc-sc-sa${local.suffix}"
  display_name    = "vpc-sc-service-acct${local.suffix}"
}
data "google_service_account_access_token" "sa" {
  target_service_account  = google_service_account.vpc_sc_sa.email
  lifetime                = "600s"
  scopes                  = [
    "https://www.googleapis.com/auth/cloud-platform",
  ]
}

resource "google_organization_iam_member" "vpc_sc_member" {
  org_id  = var.parent_id
  role    = "roles/accesscontextmanager.policyAdmin"
  member  = "serviceAccount:${google_service_account.vpc_sc_sa.email}"
}

resource "google_project_iam_member" "sa_roles" {
  for_each  = {for item in local.roles_per_project: "${item.role}_${item.project}" => item}
  project   = each.value.project
  role      = each.value.role
  member    = google_service_account.vpc_sc_sa.member
}
provider "google" {
  billing_project = var.protected_project_ids[0]
  project         = var.protected_project_ids[0]
  access_token    = data.google_service_account_access_token.sa.access_token
  alias           = "impersonation"
}
provider "google-beta" {
  billing_project = var.protected_project_ids[0]
  project         = var.protected_project_ids[0]
  access_token    = data.google_service_account_access_token.sa.access_token
  alias           = "impersonation"
}

data "google_client_config" "default" {
}
data "google_project" "protected_projects" {
  for_each = toset(var.protected_project_ids)
  project_id  = each.value
}

data "google_project" "unprotected_projects" {
  for_each = toset(var.unprotected_project_ids)
  project_id  = each.value
}

data "google_projects" "parents" {
  filter = "parent.type:folder AND (${join(" OR ", formatlist("id:%s",var.protected_project_ids))})"
  #distinct(data.google_projects.parents.projects.*.parent.id)
}

resource "google_access_context_manager_access_policy" "access_policy" {
  parent        = "organizations/${var.parent_id}"
  provider      = google.impersonation
  title         = "Access policy ${local.suffix_nodash}"
  depends_on    = [ google_organization_iam_member.vpc_sc_member ]
  scopes        = formatlist("folders/%s",distinct(data.google_projects.parents.projects.*.parent.id))
}

resource "google_access_context_manager_service_perimeter" "service_perimeter" {
  provider    = google.impersonation
  parent      = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}"
  name        = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}/servicePerimeters/perim${local.suffix_nodash}"
  title       = "Restrict APIs ${local.suffix_nodash}"
  status {
    restricted_services = var.restricted_services
    resources           = formatlist("projects/%s",values(data.google_project.protected_projects)[*].number)
    ingress_policies {
      title = "Service Account access from Terraform to perform CRUD operations to protected services"
      ingress_from {
        identities = ["serviceAccount:${google_service_account.vpc_sc_sa.email}"]
        sources {
          access_level = "*"
        }
      }
      ingress_to {
        #resources = formatlist("projects/%s",values(data.google_project.protected_projects)[*].number)
        resources =  ["*"]
        operations {
          service_name = "*"
        }
      }
    }
    egress_policies {
      title = "Service Account access to perform CRUD operations on projects outside the perimeter"
      egress_from {
        identities = ["serviceAccount:${google_service_account.vpc_sc_sa.email}"]
      }
      egress_to {
        resources = [ "*" ]
        operations {
          service_name = "*"
        }
      }
    }
  }
}

module "google-infra-vpc" {
  providers     = {
    google      = google.impersonation
  }
  source      = "/home/mhanline/terraform/terraform-examples/modules/google-infra-vpc"
  vpcs        = var.vpcs
  namesuffix  = local.suffix_nodash
  depends_on = [ google_project_iam_member.sa_roles, google_access_context_manager_service_perimeter.service_perimeter ]
  ignore_nested_deprecations = true
}

# GCS Bucket testing

resource "google_storage_bucket" "gcs_bucket_protected" {
  provider      = google.impersonation
  project       = var.protected_project_ids[0]
  name          = "protectedbucket${local.suffix}"
  storage_class = "MULTI_REGIONAL"
  location      = "ASIA"
  depends_on = [
    google_access_context_manager_service_perimeter.service_perimeter, google_project_iam_member.sa_roles
  ]
}

resource "google_storage_bucket" "gcs_bucket_unprotected" {
  provider      = google.impersonation
  project       = var.unprotected_project_ids[0]
  name          = "unprotectedbucket${local.suffix}"
  storage_class = "MULTI_REGIONAL"
  location      = "ASIA"
  depends_on = [
    google_access_context_manager_service_perimeter.service_perimeter, google_project_iam_member.sa_roles
  ]
}

resource "google_storage_bucket_iam_member" "all_users_viewers_protected" {
  provider  = google.impersonation
  bucket    = google_storage_bucket.gcs_bucket_protected.name
  role      = "roles/storage.legacyObjectReader"
  member    = "allUsers"
}
resource "google_storage_bucket_iam_member" "all_users_viewers_unprotected" {
  provider  = google.impersonation
  bucket    = google_storage_bucket.gcs_bucket_unprotected.name
  role      = "roles/storage.legacyObjectReader"
  member    = "allUsers"
}

resource "google_storage_bucket_object" "file_protected" {
  provider      = google.impersonation
  name          = "test_file.txt"
  source        = "./test_file.txt"
  bucket        = google_storage_bucket.gcs_bucket_protected.name
}

resource "google_storage_bucket_object" "file_unprotected" {
  provider      = google.impersonation
  name          = "test_file.txt"
  source        = "./test_file.txt"
  bucket        = google_storage_bucket.gcs_bucket_unprotected.name
}

resource "google_compute_instance" "testvms" {
  provider            = google.impersonation
  for_each            = { for vm in var.vms : vm.name => vm }
  project             = each.value.project
  name                = "${each.key}${local.suffix}"
  machine_type        = each.value.size
  zone                = random_shuffle.gcp_zones[each.value.region].result[0]
  metadata            = {
      startup-script      = templatefile("debian-client.sh.tftpl", {
          protected-bkt   = "${google_storage_bucket.gcs_bucket_protected.url}/${google_storage_bucket_object.file_protected.output_name}"
          unprotected-bkt = "${google_storage_bucket.gcs_bucket_unprotected.url}/${google_storage_bucket_object.file_unprotected.output_name}"
      })
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
    access_config {
      // Ephemeral public IP
    }
  }
  service_account {
      scopes = ["cloud-platform"]
  }
  depends_on  = [
    #google_dns_record_set.swp_proxy_record_set,
    google_project_iam_member.sa_roles,
    google_access_context_manager_service_perimeter.service_perimeter
  ]
}

data "google_netblock_ip_ranges" "ip_ranges" {
  provider            = google.impersonation
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

resource "google_compute_network_firewall_policy" "fw_policy" {
  provider    = google.impersonation
  for_each    = module.google-infra-vpc.vpcs
  name        = "fwp-${each.value.name}-${substr(md5(each.key),0,4)}"
  project     = each.value.project
  description = each.value.name
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  provider            = google.impersonation
  for_each            = google_compute_network_firewall_policy.fw_policy
  project		          = each.value.project
  name                = "fpa-${each.value.description}-${substr(md5(each.key),0,4)}"
  attachment_target   = module.google-infra-vpc.vpcs[each.key].id
  firewall_policy     = each.value.id
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
  provider            = google.impersonation
  for_each            = google_compute_network_firewall_policy.fw_policy
  project		          = each.value.project
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = each.value.id
  priority                = 200
  rule_name               = "iap-allow${local.suffix}-${substr(md5(each.key),0,4)}"
  match {
      src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["iap-forwarders"].cidr_blocks_ipv4
      layer4_configs {
        ip_protocol = "tcp"
        ports = [22]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "rfc1918_rule" {
  provider            = google.impersonation
  for_each            = google_compute_network_firewall_policy.fw_policy
  project		          = each.value.project
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = each.value.id
  priority                = 20000
  rule_name               = "rfc1918-allow${local.suffix}-${substr(md5(each.key),0,4)}"
  match {
    src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_global_address" "psc_ip" {
  provider      = google.impersonation
  for_each      = module.google-infra-vpc.vpcs
  project		    = each.value.project
  name          = "psc-gapis-${substr(md5(each.key),0,4)}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = each.value.id
  address       = "192.168.88.88"
}

resource "google_compute_global_address" "vpc-sc_psc_ip" {
  provider      = google.impersonation
  for_each      = module.google-infra-vpc.vpcs
  project		    = each.value.project
  name          = "psc-vpcsc-${substr(md5(each.key),0,4)}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = each.value.name
  address       = "192.168.99.99"
}

resource "google_compute_global_forwarding_rule" "apis_forwarding_rule" {
  provider              = google.impersonation
  project		            = each.value.project
  for_each              = google_compute_global_address.psc_ip
  name                  = "allapis${substr(md5(each.key),0,8)}"
  target                = "all-apis"
  network               = module.google-infra-vpc.vpcs[each.key].id
  ip_address            = each.value.address
  load_balancing_scheme = ""
}

resource "google_compute_global_forwarding_rule" "vpc-sc_forwarding_rule" {
  provider              = google.impersonation
  project		            = each.value.project
  for_each              = google_compute_global_address.vpc-sc_psc_ip
  name                  = "vpcsc${substr(md5(each.key),0,8)}"
  target                = "vpc-sc"
  network               = module.google-infra-vpc.vpcs[each.key].id
  ip_address            = each.value.address
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis" {
  provider              = google.impersonation
  for_each              = module.google-infra-vpc.vpcs
  project		            = each.value.project
  response_policy_name  = "dns-rp-${substr(md5(each.key),0,8)}"
  networks {
    network_url = each.value.id
  }
}

resource "google_dns_response_policy_rule" "googleapis" {
  provider        = google.impersonation
  for_each        = {
    for y in setproduct(var.dns_rp_rules,values(module.google-infra-vpc.vpcs)) : "${y[1].identifier}-${y[0].name}" => y
  }
  response_policy = google_dns_response_policy.googleapis[each.value[1].identifier].response_policy_name
  project         = each.value[1].project
  rule_name       = "${each.value[0].name}-${substr(md5(each.key),0,4)}"
  dns_name        = each.value[0].dns_name
  local_data {
    local_datas {
      name    = each.value[0].dns_name
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc_ip["${each.value[1].identifier}"].address]
    }
  }
}
