#! /bin/bash

# Make bash easier on Debian
cat <<EOF > /etc/skel/.bash_aliases
alias la='ls -lAh'
alias ll='ls -lh'
alias lsa='ls -lah'
alias l='ls -CF'
alias grep='grep --color=auto'
EOF

apt-get remove -y --purge man-db
cat <<"EOF" > /etc/skel/pga-test.sh
#! /bin/bash
TOKEN=`gcloud auth print-access-token`
USER=`gcloud config list account --format "value(core.account)"`
PROJECT_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")
ZONE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | awk -F "/" '{print $NF}')
set -x
curl https://storage.googleapis.com/wowvpc-sc/insideperim.txt
curl https://storage.googleapis.com/mhanline-pub/outsideperim.txt

#Simulate using restricted.googleapis.com
curl --resolve storage.googleapis.com:443:199.36.153.5 https://storage.googleapis.com/mhanline-pub/outsideperim.txt
curl -H "Authorization: Bearer $TOKEN" https://oslogin.googleapis.com/v1/users/$USER/loginProfile
curl -H "Authorization: Bearer $TOKEN" https://compute.googleapis.com/compute/v1/projects/${PROJECT_NAME}/zones/${ZONE_NAME}/instances
EOF
chmod a+x /etc/skel/pga-test.sh
