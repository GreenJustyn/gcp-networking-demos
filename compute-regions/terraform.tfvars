project-id  = "mhanline-playpen001"
apis = [
  "compute.googleapis.com"
]
# Use [] for no filter. Otherwise, filter by region using a list such as "australia-", "us-"
region_filter = ["asia-southeast1"]
# Vms per region distributes each VM across a zone each, wrapping back to the first.
vms_per_region = 2
external_ip = true #does nothing currently. Need to add.