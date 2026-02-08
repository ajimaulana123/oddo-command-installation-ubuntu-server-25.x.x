#!/bin/bash
# ODOO 19 Installation Script for Ubuntu 22.04 LTS
# Save as: install-odoo19-ubuntu22.sh

set -e

echo "=========================================="
echo "Installing Odoo 19 on Ubuntu 22.04 LTS"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root or with sudo"
    exit 1
fi

# System Information
echo "System Information:"
echo "-------------------"
lsb_release -a
echo ""

# Update System
print_status "Updating system packages..."
apt update
apt upgrade -y

# Install Required Dependencies
print_status "Installing system dependencies..."
apt install -y wget curl git build-essential python3 python3-venv python3-dev python3-pip \
libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev \
libpq-dev libjpeg-dev libopenjp2-7-dev libfreetype6-dev libffi-dev \
libmysqlclient-dev liblcms2-dev libblas-dev libatlas-base-dev gfortran \
libgeoip-dev libpcre3-dev libyaml-dev libjpeg-turbo8-dev libwebp-dev \
libtiff5-dev libraqm-dev libxslt-dev libzip-dev libreadline-dev \
libxmlsec1-dev pkg-config

# Install Node.js for Odoo web interface
print_status "Installing Node.js and NPM..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Install PostgreSQL 14 (default for Ubuntu 22.04)
print_status "Installing PostgreSQL 14..."
apt install -y postgresql postgresql-contrib postgresql-server-dev-14

# Install Redis for caching
print_status "Installing Redis..."
apt install -y redis-server

# Install wkhtmltopdf
print_status "Installing wkhtmltopdf..."
# Method 1: Try from Ubuntu repo
apt install -y wkhtmltopdf || \
# Method 2: Download from GitHub
wget -O /tmp/wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb && \
apt install -y /tmp/wkhtmltox.deb && \
rm /tmp/wkhtmltox.deb || \
print_warning "wkhtmltopdf installation failed, continuing anyway..."

# Create Odoo System User
print_status "Creating Odoo system user..."
if id "odoo" &>/dev/null; then
    print_warning "User 'odoo' already exists"
else
    useradd -m -d /opt/odoo -U -r -s /bin/bash odoo
    print_status "User 'odoo' created successfully"
fi

# Create Required Directories
print_status "Creating directories..."
mkdir -p /opt/odoo/odoo19
mkdir -p /opt/odoo/venv/odoo19
mkdir -p /opt/odoo/custom-addons
mkdir -p /opt/odoo/backups
mkdir -p /var/log/odoo
mkdir -p /var/lib/odoo

# Set Permissions
chown -R odoo:odoo /opt/odoo
chown odoo:odoo /var/log/odoo
chown odoo:odoo /var/lib/odoo

# Clone Odoo 19 Source Code
print_status "Downloading Odoo 19 source code..."
cd /opt/odoo
if [ -d "/opt/odoo/odoo19" ] && [ "$(ls -A /opt/odoo/odoo19)" ]; then
    print_warning "Odoo directory exists, pulling latest changes..."
    cd odoo19
    sudo -u odoo git pull origin 19.0
else
    sudo -u odoo git clone https://github.com/odoo/odoo.git odoo19 --depth 1 --branch 19.0
fi

# Create Python Virtual Environment
print_status "Creating Python virtual environment..."
cd /opt/odoo
if [ ! -d "/opt/odoo/venv/odoo19/bin" ]; then
    sudo -u odoo python3 -m venv venv/odoo19
    print_status "Virtual environment created"
else
    print_warning "Virtual environment already exists"
fi

# Activate venv and install Python dependencies
print_status "Installing Python packages..."
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install --upgrade pip setuptools wheel
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install -r /opt/odoo/odoo19/requirements.txt

# Additional packages for Odoo 19
print_status "Installing additional Python packages..."
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install psycopg2-binary pillow \
ldap3 python-ldap num2words phonenumbers pdfminer.six xlrd \
pyOpenSSL jinja2 qrcode libsass lxml polib babel passlib \
pysftp cryptography decorator docutils ebaysdk feedparser \
gevent greenlet html2text idna isodate jdcal oauthlib ofxparse \
paramiko pbr pdfminer.six pydot pyparsing pypdf2 python-dateutil \
python-stdnum pytz pyusb reportlab requests rjsmin suds-jurko \
vatnumber vobject werkzeug xlwt xlrd zeep

# Create Odoo Configuration File
print_status "Creating Odoo configuration file..."
cat > /etc/odoo19.conf << 'EOF'
[options]
; Basic Configuration
admin_passwd = admin
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = /opt/odoo/odoo19/addons,/opt/odoo/custom-addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo19.log
log_level = info

; Network Configuration
xmlrpc_port = 8069
longpolling_port = 8072
proxy_mode = True

; Performance Optimization
workers = 4
max_cron_threads = 1
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200

; Database Configuration
db_maxconn = 64
db_template = template0
list_db = True
dbfilter = .*

; Security
csv_insecure_separator = False
smtp_password = False
smtp_port = 25
smtp_server = localhost
smtp_ssl = False
smtp_user = False

; Email Configuration
email_from = False
smtp_password = False
smtp_port = 25
smtp_server = localhost
smtp_ssl = False
smtp_user = False
EOF

chown odoo:odoo /etc/odoo19.conf
chmod 640 /etc/odoo19.conf

# Configure PostgreSQL for Odoo
print_status "Configuring PostgreSQL..."
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser --no-password odoo 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER odoo WITH PASSWORD 'odoo';" 2>/dev/null || true

# Adjust PostgreSQL configuration for better performance
PG_CONFIG="/etc/postgresql/14/main/postgresql.conf"
if [ -f "$PG_CONFIG" ]; then
    # Backup original config
    cp "$PG_CONFIG" "$PG_CONFIG.backup_$(date +%Y%m%d_%H%M%S)"
    
    # Update settings
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONFIG"
    sed -i "s/#shared_buffers = 128MB/shared_buffers = 256MB/" "$PG_CONFIG"
    sed -i "s/#work_mem = 4MB/work_mem = 16MB/" "$PG_CONFIG"
    sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = 128MB/" "$PG_CONFIG"
    
    print_status "PostgreSQL configuration updated"
    
    # Restart PostgreSQL
    systemctl restart postgresql
fi

# Create Systemd Service File
print_status "Creating systemd service..."
cat > /etc/systemd/system/odoo19.service << 'EOF'
[Unit]
Description=Odoo 19
Requires=postgresql.service
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
SyslogIdentifier=odoo19
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/venv/odoo19/bin/python3 /opt/odoo/odoo19/odoo-bin -c /etc/odoo19.conf
StandardOutput=journal+console
Restart=always
RestartSec=5
TimeoutStartSec=600
KillMode=mixed
Environment="PATH=/opt/odoo/venv/odoo19/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONPATH=/opt/odoo/odoo19"

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/odoo /var/log/odoo /opt/odoo

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable services
print_status "Starting Odoo service..."
systemctl daemon-reload
systemctl enable odoo19
systemctl start odoo19

# Wait for service to start
print_status "Waiting for Odoo to start..."
sleep 10

# Check if service is running
if systemctl is-active --quiet odoo19; then
    print_status "Odoo service is running successfully"
else
    print_error "Odoo service failed to start"
    journalctl -u odoo19 --no-pager -n 20
    exit 1
fi

# Create Firewall Rules (if ufw is active)
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    print_status "Configuring firewall..."
    ufw allow 8069/tcp
    ufw allow 8072/tcp
    ufw reload
fi

# Create Monitoring Script
print_status "Creating monitoring scripts..."

# Disk space monitoring
cat > /opt/odoo/check_disk.sh << 'EOF'
#!/bin/bash
echo "=== Odoo Disk Usage Monitor ==="
echo "Date: $(date)"
echo ""
echo "Overall Disk Usage:"
df -h
echo ""
echo "Odoo Directory Usage:"
du -sh /opt/odoo/* 2>/dev/null
echo ""
echo "Log Directory Usage:"
du -sh /var/log/odoo/* 2>/dev/null 2>/dev/null
echo ""
echo "PostgreSQL Database Sizes:"
sudo -u postgres psql -c "
SELECT 
    datname as \"Database\",
    pg_size_pretty(pg_database_size(datname)) as \"Size\",
    age(datfrozenxid) as \"Transaction Age\"
FROM pg_database
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;
" 2>/dev/null || echo "Cannot access PostgreSQL"
EOF

chmod +x /opt/odoo/check_disk.sh
chown odoo:odoo /opt/odoo/check_disk.sh

# Service status check
cat > /opt/odoo/check_status.sh << 'EOF'
#!/bin/bash
echo "=== Odoo Service Status ==="
echo "Date: $(date)"
echo ""
echo "Odoo Service:"
systemctl status odoo19 --no-pager | head -20
echo ""
echo "PostgreSQL Service:"
systemctl status postgresql --no-pager | head -10
echo ""
echo "Redis Service:"
systemctl status redis-server --no-pager | head -10
echo ""
echo "Active Connections:"
sudo -u postgres psql -c "SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null || echo "Cannot check connections"
EOF

chmod +x /opt/odoo/check_status.sh
chown odoo:odoo /opt/odoo/check_status.sh

# Create Backup Script
cat > /opt/odoo/backup.sh << 'EOF'
#!/bin/bash
# Odoo Backup Script
BACKUP_DIR="/opt/odoo/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/odoo_backup_$DATE.tar.gz"

echo "Starting Odoo backup at $(date)"

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR"

# Backup database
echo "Backing up database..."
sudo -u postgres pg_dump odoo > "/tmp/odoo_db_$DATE.sql" 2>/dev/null || \
sudo -u postgres pg_dumpall > "/tmp/odoo_all_$DATE.sql"

# Backup filestore
echo "Backing up filestore..."
tar -czf "$BACKUP_FILE" \
    "/tmp/odoo_db_$DATE.sql" \
    "/var/lib/odoo" \
    "/etc/odoo19.conf" \
    "/opt/odoo/custom-addons" 2>/dev/null

# Cleanup temp files
rm -f "/tmp/odoo_db_$DATE.sql" "/tmp/odoo_all_$DATE.sql"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "odoo_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
echo "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
EOF

chmod +x /opt/odoo/backup.sh
chown odoo:odoo /opt/odoo/backup.sh

# Create daily backup cron job
echo "0 2 * * * /opt/odoo/backup.sh" | sudo -u odoo crontab -

# Display Installation Summary
IP_ADDRESS=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDRESS" ]; then
    IP_ADDRESS="localhost"
fi

echo ""
echo "=========================================="
echo "🎉 ODOO 19 INSTALLATION COMPLETED 🎉"
echo "=========================================="
echo ""
echo "📊 SYSTEM INFORMATION:"
echo "   Ubuntu Version:  $(lsb_release -ds)"
echo "   Python Version:  $(python3 --version)"
echo "   PostgreSQL:      14"
echo "   Odoo Version:    19.0"
echo ""
echo "🌐 ACCESS INFORMATION:"
echo "   URL:             http://$IP_ADDRESS:8069"
echo "   Master Password: admin"
echo ""
echo "⚙️ SERVICE COMMANDS:"
echo "   Check status:    sudo systemctl status odoo19"
echo "   View logs:       sudo journalctl -u odoo19 -f"
echo "   Restart:         sudo systemctl restart odoo19"
echo "   Stop:            sudo systemctl stop odoo19"
echo ""
echo "📁 DIRECTORY STRUCTURE:"
echo "   Odoo Source:     /opt/odoo/odoo19"
echo "   Virtual Env:     /opt/odoo/venv/odoo19"
echo "   Custom Addons:   /opt/odoo/custom-addons"
echo "   Backups:         /opt/odoo/backups"
echo "   Logs:            /var/log/odoo/"
echo "   Config:          /etc/odoo19.conf"
echo ""
echo "🔧 UTILITY SCRIPTS:"
echo "   Check disk:      /opt/odoo/check_disk.sh"
echo "   Check status:    /opt/odoo/check_status.sh"
echo "   Backup:          /opt/odoo/backup.sh"
echo ""
echo "⚠️ IMPORTANT:"
echo "   1. Change the master password immediately!"
echo "   2. Configure proper firewall rules"
echo "   3. Set up SSL/TLS for production"
echo "   4. Regular backups are stored in /opt/odoo/backups"
echo ""
echo "=========================================="
echo "Need help? Check logs: sudo journalctl -u odoo19"
echo "=========================================="
