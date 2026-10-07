#!/bin/bash

# Check if user is root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

echo "Installing Nginx..."

# Ubuntu / Debian
if [ -f /etc/debian_version ]; then
    apt update
    apt install nginx -y

# RHEL / CentOS / Rocky
elif [ -f /etc/redhat-release ]; then
    yum install nginx -y
fi

# Start Nginx
systemctl start nginx

# Enable Nginx at boot
systemctl enable nginx

# Create test page
mkdir -p /var/www/html

cat <<EOF > /var/www/html/index.html
<html>
<head>
<title>Nginx Test</title>
</head>
<body>
<h1>Nginx Installation Successful</h1>
</body>
</html>
EOF

# Check Nginx configuration
nginx -t

# Restart service
systemctl restart nginx

echo "Nginx installation completed."

echo "Nginx Status:"
systemctl status nginx --no-pager

echo "Access URL:"
echo "http://<server-ip>"

