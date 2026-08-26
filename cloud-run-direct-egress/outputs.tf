
output "ext_ip" {
  description = ""
  value       = "http://${google_compute_global_forwarding_rule.frontend.ip_address}:${split("-",google_compute_global_forwarding_rule.frontend.port_range)[0]}/"
}

output "cloud_run_url" {
  description = ""
  value       = google_cloud_run_v2_service.json_svc.uri
}