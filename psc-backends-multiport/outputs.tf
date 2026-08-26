output psc_consumer_ip {
    value = values(google_compute_forwarding_rule.psc_consumer_fr).*.ip_address[0]
}
output psc_producer_ips {
    value = [for i in values(google_compute_forwarding_rule.producer_forwarding_rule): "https://${i.ip_address}:${split("-", i.port_range)[0]}"]
}