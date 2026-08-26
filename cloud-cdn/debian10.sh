#!/bin/bash

# Make bash easier on Debian
cat <<EOF > /etc/skel/.bash_aliases
alias la='ls -lAh'
alias ll='ls -lh'
alias lsa='ls -lah'
alias l='ls -CF'
alias grep='grep --color=auto'
EOF
apt update
apt -y install apache2
cat <<EOF > /var/www/html/index.html
<html><body><h1>Hello World</h1>
<p>This page was created from a startup script.</p>
</body></html>
EOF