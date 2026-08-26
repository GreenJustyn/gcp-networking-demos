output "fw_policy" { value = google_compute_network_firewall_policy.fw_policy }
output "fw_pol_aassoc" { value = google_compute_network_firewall_policy_association.fw_policy_assoc }
output "tag_key" { value = local.tag_key }
output "tag_value" { value = local.tag_value }
#output "google_tags_tag_key" { value = google_tags_tag_key.fw_tag_key }
#output "google_tags_tag_value" { value = google_tags_tag_value.fw_tag_value }
#output "google_tags_tab_binding" { value = google_tags_tag_binding.tag_binding }