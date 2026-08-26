# Outputs for use in the rest of the demo
output project-id {
  value = var.project-id
}
output region-1 {
  value = local.regions[0]
}
output vpcnet {
  value = google_compute_network.vpc.name
}
output subnet-a {
  value = google_compute_subnetwork.region-a-sub.name
}
