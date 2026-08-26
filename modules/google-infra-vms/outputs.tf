output "instances" { value = google_compute_instance.instances }
output "sa" { value = data.google_compute_default_service_account.default_sa }
output "vm_image" { value=data.google_compute_image.compute_image }
output "zones" { value=random_shuffle.region_zones }
