/*
output host_ip {
    value = google_compute_instance.host_instance.network_interface[0].network_ip
}

output client_ip { 
    value = google_compute_instance.client_instance.network_interface[0].network_ip
}
*/