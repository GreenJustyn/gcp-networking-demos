#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
/*
output "vpcname" {
    value = module.google-infra-vpc.vpcs[var.vpcs[0].network].name
}
output "subnets" {
    value = {for key, val in module.google-infra-vpc.subnets: val.name => val.region if val.purpose == "PRIVATE"}
}

output "swp_hostname" {
    value = trimsuffix(google_dns_managed_zone.swp-private-zone.dns_name, ".")
}

output "certificate_name" {
    value = {for cert_id in google_certificate_manager_certificate.secure-web-proxy-cert : cert_id.id => cert_id.location}
}

output "ca_pools" {
    value = {for entry in google_privateca_ca_pool.swp-tlsinsp-ca-subpool : entry.location => entry.id }
}
*/