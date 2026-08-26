output alb_url {
    value = "http://${google_compute_global_forwarding_rule.default.ip_address}:${split("-",google_compute_global_forwarding_rule.default.port_range)[0]}"
}