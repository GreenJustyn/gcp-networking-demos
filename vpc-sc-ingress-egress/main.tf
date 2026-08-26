#FYI: You need to add a role to your own account, Service Account Token Creator, to allow it to impersonate the service account.

terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.38"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 6.38"
    }
  }
}

##### Use this new data source#####
data "google_project_ancestry" "example" {
    for_each = { for project in var.project-ids: project => null }
    project_id = each.key
}
######

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    apis_per_project  = flatten([
        for project in var.project-ids: [
            for api in var.apis: {
                api_name    = api
                project_id  = project
            }
        ]
    ])
}
resource "random_id" "id" {
	byte_length = 3
}

data "google_client_config" "default" {
}

data "google_project" "project" {
    for_each    = toset(var.project-ids)
    project_id  = each.value
}

resource "google_service_account" "sa-name" {
    account_id      = "vpc-sc-sa${local.suffix}"
    display_name    = "vpc-sc-service-acct${local.suffix}"
}

data "google_service_account_access_token" "sa" {
    target_service_account  = google_service_account.sa-name.email
    lifetime                = "300s"
    scopes                  = [
        "https://www.googleapis.com/auth/cloud-platform",
    ]
}

#To-do make these variables and for_each
resource "google_project_iam_member" "serviceUsageConsumer" {
    project = google_service_account.sa-name.project
    role    = "roles/serviceusage.serviceUsageConsumer"
    member  = google_service_account.sa-name.member
}

resource "google_project_iam_member" "CloudRun" {
    project = google_service_account.sa-name.project
    role    = "roles/run.admin"
    member  = google_service_account.sa-name.member
}

resource "google_project_iam_member" "CloudRun-actas" {
    project = google_service_account.sa-name.project
    role    = "roles/iam.serviceAccountUser"
    member  = google_service_account.sa-name.member
}

provider "google" {
    access_token    = data.google_service_account_access_token.sa.access_token
    project         = var.project-ids[0]
    alias           = "impersonation"
}
provider "google" {
  project     = var.project-ids[0]
}

resource "google_compute_project_metadata" "default" {
    for_each    = toset(var.project-ids)
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "vpc-sc-ingress-egress${local.suffix}-cwd" = path.cwd
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
    member      = "serviceAccount:${google_service_account.sa-name.email}"
}

resource "google_access_context_manager_access_level" "access-level" {
    provider    = google.impersonation
    parent      = "accessPolicies/${google_access_context_manager_access_policy.access-policy.id}"
    name        = "accessPolicies/${google_access_context_manager_access_policy.access-policy.id}/accessLevels/policy${local.suffix_nodash}"
    title       = "allow service accounts into perimeter"
    basic {
        conditions {
            members = [
                google_service_account.sa-name.member
            ]
        }
    }
}

resource "google_access_context_manager_access_policy" "access-policy" {
  parent        = "organizations/${var.parent_id}"
  provider      = google.impersonation
  title         = "access context manager access policy for ${local.suffix_nodash}"
}

resource "google_access_context_manager_service_perimeter" "service-perimeter" {
    for_each    = var.vpc_sc_perimeters
    provider    = google.impersonation
    parent      = "accessPolicies/${google_access_context_manager_access_policy.access-policy.name}"
    name        = "accessPolicies/${google_access_context_manager_access_policy.access-policy.name}/servicePerimeters/${each.key}"
    title       = "${each.key} Restrict APIs"
    status {
        restricted_services = var.protected_apis
        resources           = [ for item in each.value: "projects/${data.google_project.project[item].number}"]
        #resources           = flatten([for item in data.google_project.project: [for key,value in item: "projects/${value}" if key == "number" ]])
        access_levels       = [ google_access_context_manager_access_level.access-level.name ]

    }
}

resource "google_access_context_manager_service_perimeter_ingress_policy" "ingress_policy" {
    provider    = google.impersonation
    perimeter   = google_access_context_manager_service_perimeter.service-perimeter["perimeter1"].name
    ingress_from {
        identity_type   = "ANY_IDENTITY"
        #sources {
        #    #resource    = "projects/${data.google_project.project[var.project-ids[1]].number}"
        #    access_level = "*"
        #}
    }
    ingress_to  {
        resources   = ["*"]
        
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

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

#
# Cloud Run Service
#

resource "google_cloud_run_v2_service" "json_svc" {
    provider    = google.impersonation
    name        = "cloudrun-juiceshop${local.suffix}"
    location    = var.region
    project     = google_project_iam_member.CloudRun.project
    ingress     = "INGRESS_TRAFFIC_INTERNAL_ONLY"
    template {
        containers {
            #image = "codfish/json-server:0.17.3"
            image   = "bkimminich/juice-shop"
            startup_probe {
                initial_delay_seconds = 0
                timeout_seconds = 240
                period_seconds = 240
                failure_threshold = 1
                tcp_socket {
                    #port = 80
                    port = 3000
                }
            }
            ports {
                #container_port = 80
                container_port = 3000
            }
        }
    }
}

resource "google_cloud_run_service_iam_binding" "public_cloud_run" {
    provider    = google.impersonation
    location    = google_cloud_run_v2_service.json_svc.location
    service     = google_cloud_run_v2_service.json_svc.name
    role        = "roles/run.invoker"
    members     = [
        "allUsers"
    ]
}

# DNS #
/*
resource "google_dns_managed_zone" "google-apis" {
    for_each    = toset(var.project-ids)
    name        = "zone-${local.suffix}"
    project     = each.value
    dns_name    = "googleapis.com."
    description = "private zone for Google APIs"
    visibility = "private"
    private_visibility_config {
        networks {
            network_url = google_compute_network.vpcsc-net.self_link
        }
    }
}

resource "google_dns_record_set" "restricted-google-apis-A-record" {
  name    = "restricted.googleapis.com."
  project = var.project-id
  type    = "A"
  ttl     = 300
  managed_zone = google_dns_managed_zone.google-apis.name
  rrdatas = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
}

resource "google_dns_record_set" "google-api-CNAME" {
  name    = "*.googleapis.com."
  project = var.project-id
  type    = "CNAME"
  ttl     = 300
  managed_zone = google_dns_managed_zone.google-apis.name
  rrdatas = ["restricted.googleapis.com."]
}
*/