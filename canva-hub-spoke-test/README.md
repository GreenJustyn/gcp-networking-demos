# NCC Hub/Spoke Testing

```
terraform init
terraform plan
terraform apply
```
This creates the Hub and 2 spokes with VPC Peering

## NCC Hub and Spokes
This creates NCC Hub and Spokes

```
gcloud config set project <your-project-id>
terraform output
```
Create the hub:
```
gcloud network-connectivity hubs create my-hub 
```
Create the spokes:
```
#Take the output from:
terraform output spoke_ids && tf output hub_id to make the spokes
gcloud network-connectivity spokes linked-vpc-network create hub-spoke-1  --hub=my-hub  --vpc-network=projects/mhanline-ncc-01/global/networks/vpc-spoke-1-5af1b5 --global
```

## Listing / Troubleshooting

```
gcloud network-connectivity hubs route-tables routes list   --hub=my-hub   --route_table=default
```

## Cleanup

```
gcloud network-connectivity spokes delete hub-spoke-1 --global -q
gcloud network-connectivity spokes delete hub-spoke-2 --global -q
gcloud network-connectivity hubs delete my-hub -q
```