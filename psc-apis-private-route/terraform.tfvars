project-id = "mhanline-sand06"
nameprefix = "sme2020-td"
deploy_test_vms = true #To-Do: conditional resource here
vm_spec = "e2-small" # Used for test VMs
zoneregions = {
      "asia-southeast1" = ["asia-southeast1-b"],
      "us-central1" = ["us-central1-c"],
}
# Add subnets, one per each region. Must match items of zoneregions.
subnets = [
    "10.11.0.0/22",
    "10.11.4.0/22"
]
apis = [
  "compute.googleapis.com",
  "trafficdirector.googleapis.com",
  "pubsub.googleapis.com",
  "container.googleapis.com",
  "oslogin.googleapis.com"
]
psc_ips = [
    {
        network     = "net-swg-demo"
        name        = "psc"
        address     = "10.252.252.101"
    }
]
dns_rp_rules = [
    {
        name        = "googleapis-com-rule"
        psc-ip      = "psc"
        dns_name    = "*.googleapis.com."
    },
    {
        name        = "packagamanager-rule"
        psc-ip      = "psc"
        dns_name    = "packages.cloud.google.com."
    },
    {
        name        = "dl-google-com-rule"
        psc-ip      = "psc"
        dns_name    = "dl.google.com."
    }
]