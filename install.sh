#!/bin/bash

# ODOO 19 Installation Script for Ubuntu 25.10
# Save as: install.sh

set -e

echo "=========================================="
echo "Installing Odoo 19 on Ubuntu 25.10"
echo "=========================================="

# Update System
echo "Updating system..."
sudo apt update
sudo apt upgrade -y

# Install Dependencies
echo "Installing dependencies..."
sudo apt install -y wget curl git build-essential python3.12 python3.12-venv \
python3.12-dev python3-pip libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev \
libldap2-dev libssl-dev libpq-dev libjpeg-dev libopenjp2-7-dev libfreetype6-dev \
libffi-dev libmysqlclient-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev \
gfortran nodejs npm redis-server libgeoip-dev libmaxminddb-dev libpcre3-dev

# Install PostgreSQL 17
echo "Installing PostgreSQL 17..."
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update
sudo apt install -y postgresql-17 postgresql-client-17

# Create Odoo User
echo "Creating Odoo user..."
sudo useradd -m -d /opt/odoo -U -r -s /bin/bash odoo

# Create Directories
echo "Creating directories..."
sudo mkdir -p /opt/odoo/{odoo19,venv/odoo19,custom-addons,backups}
sudo chown -R odoo:odoo /opt/odoo

# Clone Odoo 19 Source
echo "Cloning Odoo 19 source code..."
cd /opt/odoo
sudo -u odoo git clone https://github.com/odoo/odoo.git odoo19 --depth 1 --branch 19.0

# Create Virtual Environment
echo "Creating virtual environment..."
cd /opt/odoo
sudo -u odoo python3.12 -m venv venv/odoo19
source /opt/odoo/venv/odoo19/bin/activate

# Install Python Dependencies
echo "Installing Python dependencies..."
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install --upgrade pip
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install -r /opt/odoo/odoo19/requirements.txt

# Install wkhtmltopdf
echo "Installing wkhtmltopdf..."
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo apt install -y ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb
rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# Create Odoo Configuration File
echo "Creating Odoo configuration..."
sudo tee /etc/odoo19.conf << EOF
[options]
; Odoo Server Configuration
admin_passwd = admin
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = /opt/odoo/odoo19/addons,/opt/odoo/custom-addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo19.log
log_level = info
xmlrpc_port = 8069
longpolling_port = 8072
proxy_mode = True
EOF

sudo chown odoo:odoo /etc/odoo19.conf
sudo chmod 640 /etc/odoo19.conf

# Create Log Directory
sudo mkdir -p /var/log/odoo
sudo chown odoo:odoo /var/log/odoo

# Create Data Directory
sudo mkdir -p /var/lib/odoo
sudo chown odoo:odoo /var/lib/odoo

# Create Systemd Service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/odoo19.service << EOF
[Unit]
Description=Odoo 19
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo19
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/venv/odoo19/bin/python3 /opt/odoo/odoo19/odoo-bin -c /etc/odoo19.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Create PostgreSQL User
echo "Creating PostgreSQL user..."
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser --no-password odoo
sudo -u postgres psql -c "ALTER USER odoo WITH PASSWORD 'odoo';"

# Enable and Start Services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable --now odoo19

echo "=========================================="
echo "Installation Completed!"
echo "=========================================="
echo "Odoo 19 is now running on: http://$(hostname -I | awk '{print $1}'):8069"
echo "Master Password: admin"
echo ""
echo "To check status: sudo systemctl status odoo19"
echo "To view logs: sudo journalctl -u odoo19 -f"
echo "=========================================="
