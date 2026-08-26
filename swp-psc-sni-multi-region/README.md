# Secure Web Proxy Terraform

This Terraform creates an elaborate multi-region Secure Web Proxy with:
- client test VMs
    - Accessible through Identity Aware Proxy (Not exposed directly to the Internet)
    - apt updates and *.googleapis.com bypass the proxy by using Private Service Connect
    - Root certificates are installed on all the client VMs through startup-scripts
-  Root and a subordinate CA and pool per region
-  Regional DNS policy for the SWP host, so clients use a consistent proxy across all regions

# Installation

`git clone ....`

# Usage

## Deploy Terraform

Edit `terraform.tfvars` and set the `project-id` variable to your Google Cloud Project ID.

Then run Terraform:
```
terraform init
terraform apply
```

## Export environment variables

Replace `$GOOGLE_CLOUD_PROJECT` with the current project, if you need to manually use a different project to your currently selected project.

```console
export PROJECT_ID=$GOOGLE_CLOUD_PROJECT
export LOCATION1=$(terraform output -json swp_ips | jq -r 'keys_unsorted'[0])
export LOCATION2=$(terraform output -json swp_ips | jq -r 'keys_unsorted'[1])
export VPCNET=$(terraform output -raw vpcname)
export SWPHOSTNAME=$(terraform output -raw swp_hostname)
export CERTIFICATE1_NAME=$(terraform output -json certificate_name | jq -r --arg region $LOCATION1 'to_entries | .[] | select(.value == $region).key')
export CERTIFICATE2_NAME=$(terraform output -json certificate_name | jq -r --arg region $LOCATION2 'to_entries | .[] | select(.value == $region).key')
export CA_POOL1=$(terraform output -json ca_pools | jq -r --arg region $LOCATION1 '.[$region]')
export CA_POOL2=$(terraform output -json ca_pools | jq -r --arg region $LOCATION2 '.[$region]')
export SUBNET1=$(terraform output -json subnets | jq -r --arg region $LOCATION1 'to_entries | .[] | select(.value == $region).key')
export SUBNET2=$(terraform output -json subnets | jq -r --arg region $LOCATION2 'to_entries | .[] | select(.value == $region).key')
export SWP_IP1=$(terraform output -json swp_ips | jq -r '[.[]][0]')
export SWP_IP2=$(terraform output -json swp_ips | jq -r '[.[]][1]')
```

## Configure a TLS Inspection Policy

```
cat <<EOF | gcloud alpha network-security tls-inspection-policies import swp-inspect-${LOCATION1} --location=${LOCATION1}
name: projects/${PROJECT_ID}/locations/${LOCATION1}/tlsInspectionPolicies/swp-inspect-${LOCATION1}
caPool: ${CA_POOL1}
EOF
```
```
cat <<EOF | gcloud alpha network-security tls-inspection-policies import swp-inspect-${LOCATION2} --location=${LOCATION2}
name: projects/${PROJECT_ID}/locations/${LOCATION2}/tlsInspectionPolicies/swp-inspect-${LOCATION2}
caPool: ${CA_POOL2}
EOF
```

## Deploy a Security Policy

```
cat <<EOF | gcloud alpha network-security gateway-security-policies import swp-policy-${LOCATION1} --location=${LOCATION1}
description: Cloud SWP policy with TLS Inspection
name: projects/${PROJECT_ID}/locations/${LOCATION1}/gatewaySecurityPolicies/swp-policy-${LOCATION1}
tlsInspectionPolicy: projects/${PROJECT_ID}/locations/${LOCATION1}/tlsInspectionPolicies/swp-inspect-${LOCATION1}
EOF
```
```
cat <<EOF | gcloud alpha network-security gateway-security-policies import swp-policy-${LOCATION2} --location=${LOCATION2}
description: Cloud SWP policy with TLS Inspection
name: projects/${PROJECT_ID}/locations/${LOCATION2}/gatewaySecurityPolicies/swp-policy-${LOCATION2}
tlsInspectionPolicy: projects/${PROJECT_ID}/locations/${LOCATION2}/tlsInspectionPolicies/swp-inspect-${LOCATION2}
EOF
```

## Create a rule with the TLS inspection configuration

```
cat <<EOF | gcloud alpha network-security url-lists import swp-urllist-${LOCATION1}  --location=${LOCATION1}
name: projects/${PROJECT_ID}/locations/${LOCATION1}/urlLists/swp-urllist-${LOCATION1}
description: "Specified List of hostnames"
values:
  - "*google.com"
  - "*wikipedia.org"
EOF
```

```
cat <<EOF | gcloud alpha network-security gateway-security-policies rules import swp-allow-hosts-${LOCATION1} --location=${LOCATION1} --gateway-security-policy=swp-policy-${LOCATION1}
name: projects/${PROJECT_ID}/locations/${LOCATION1}/gatewaySecurityPolicies/swp-policy-${LOCATION1}/rules/swp-allow-hosts-${LOCATION1}
description: Allow wikipedia and google traffic with path index.html
basicProfile: ALLOW
enabled: true
priority: 1
sessionMatcher: inUrlList(host(), "projects/${PROJECT_ID}/locations/${LOCATION1}/urlLists/swp-urllist-${LOCATION1}")
applicationMatcher: request.path.matches('index.html')
tlsInspectionEnabled: true
EOF
```

```
cat <<EOF | gcloud alpha network-security url-lists import swp-urllist-${LOCATION2}  --location=${LOCATION2}
name: projects/${PROJECT_ID}/locations/${LOCATION2}/urlLists/swp-urllist-${LOCATION2}
description: "Specified List of hostnames"
values:
  - "*google.com"
  - "*wikipedia.org"
EOF
```

```
cat <<EOF | gcloud alpha network-security gateway-security-policies rules import swp-allow-hosts-${LOCATION2} --location=${LOCATION2} --gateway-security-policy=swp-policy-${LOCATION2}
name: projects/${PROJECT_ID}/locations/${LOCATION2}/gatewaySecurityPolicies/swp-policy-${LOCATION2}/rules/swp-allow-hosts-${LOCATION2}
description: Allow wikipedia and google traffic with path index.html
basicProfile: ALLOW
enabled: true
priority: 1
sessionMatcher: inUrlList(host(), "projects/${PROJECT_ID}/locations/${LOCATION2}/urlLists/swp-urllist-${LOCATION2}")
applicationMatcher: request.path.matches('index.html')
tlsInspectionEnabled: true
EOF
```

## Create the Gateways

```
cat <<EOF | gcloud alpha network-services gateways import swp-gw-${LOCATION1} --location=${LOCATION1}
name: projects/${PROJECT_ID}/locations/${LOCATION1}/gateways/swp-policy-${LOCATION1}
type: SECURE_WEB_GATEWAY
ports: [8080,8443]
certificateUrls: [${CERTIFICATE1_NAME}]
gatewaySecurityPolicy: projects/${PROJECT_ID}/locations/${LOCATION1}/gatewaySecurityPolicies/swp-policy-${LOCATION1}
network: projects/${PROJECT_ID}/global/networks/${VPCNET}
subnetwork: projects/${PROJECT_ID}/regions/${LOCATION1}/subnetworks/${SUBNET1}
addresses: [${SWP_IP1}]
scope: scope-${LOCATION1}
EOF
```

```
cat <<EOF | gcloud alpha network-services gateways import swp-gw-${LOCATION2} --location=${LOCATION2}
name: projects/${PROJECT_ID}/locations/${LOCATION2}/gateways/swp-policy-${LOCATION2}
type: SECURE_WEB_GATEWAY
ports: [8080,8443]
certificateUrls: [${CERTIFICATE2_NAME}]
gatewaySecurityPolicy: projects/${PROJECT_ID}/locations/${LOCATION2}/gatewaySecurityPolicies/swp-policy-${LOCATION2}
network: projects/${PROJECT_ID}/global/networks/${VPCNET}
subnetwork: projects/${PROJECT_ID}/regions/${LOCATION2}/subnetworks/${SUBNET2}
addresses: [${SWP_IP2}]
scope: scope-${LOCATION2}
EOF
```

# Test from Client VM


```
#Test connecting via IP only
curl --proxy-insecure -x https://10.229.65.199:8443 https://www.google.com/index.html -v -k
#Test connecting via hostname of proxy but without certificate trust
curl --proxy-insecure -x https://proxy.swpdemo.internal:8443 -k https://www.google.com/index.html -v
#Test connecting via FQDN and trusted certificate
curl -x https://proxy.swpdemo.internal:8443 https://winzip.com -v -k
#Test connecting via Proxy hostname with trusted certificate and root CA with TLS inspection on
curl -x https://proxy.swpdemo.internal:8443 https://www.google.com/index.html -v
```

# Cleaning Up

```
gcloud alpha network-services gateways delete swp-gw-asia-southeast1 --location=${LOCATION1} -q
gcloud alpha network-services gateways delete swp-gw-us-central1 --location=${LOCATION2} -q
gcloud alpha network-security gateway-security-policies rules delete swp-allow-hosts-${LOCATION1} --location=${LOCATION1} --gateway-security-policy=swp-policy-${LOCATION1} -q
gcloud alpha network-security gateway-security-policies rules delete swp-allow-hosts-${LOCATION2} --location=${LOCATION2}  --gateway-security-policy=swp-policy-${LOCATION2} -q
gcloud alpha network-security url-lists delete swp-urllist-${LOCATION1}  --location=${LOCATION1} -q
gcloud alpha network-security url-lists delete swp-urllist-${LOCATION2}  --location=${LOCATION2} -q
gcloud alpha network-security gateway-security-policies delete swp-policy-${LOCATION1} --location=${LOCATION1} -q
gcloud alpha network-security gateway-security-policies delete swp-policy-${LOCATION2} --location=${LOCATION2} -q
gcloud network-security tls-inspection-policies delete swp-inspect-${LOCATION1} --location=${LOCATION1} -q
gcloud network-security tls-inspection-policies delete swp-inspect-${LOCATION2} --location=${LOCATION2} -q
gcloud compute routers delete swp-autogen-router
```
