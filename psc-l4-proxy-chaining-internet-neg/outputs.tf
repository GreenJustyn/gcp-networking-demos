output "consumer_ip_addr" {
    value = google_compute_forwarding_rule.psc_ilb_consumer.ip_address
}