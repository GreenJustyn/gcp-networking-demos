output "vpcs" { value       = {for k,v in google_compute_network.vpc: k => merge(v,{"identifier"=k})} }
output "subnets" { value    = google_compute_subnetwork.subnet }
output "namesuffix" { value = local.suffix_nodash }
output "network_subnets" { value = local.network_subnets }
output "project_vpcs" { value = {for item in google_compute_network.vpc: item.project => item...}}
output "project_subnets" { value = {for item in google_compute_subnetwork.subnet: item.project => item...}}