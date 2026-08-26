output "namesuffix" { value = local.suffix_nodash }
output "vpc_fw_rules" { value = google_compute_firewall.vpc_firewall_rules }