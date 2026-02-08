#!/bin/bash
# ODOO 19 Installation Script for Ubuntu 25.10
# Save as: install-odoo19.sh

set -e

echo "=========================================="
echo "Installing Odoo 19 on Ubuntu 25.10"
echo "=========================================="

# Cek versi Ubuntu
echo "Checking Ubuntu version..."
UBUNTU_VERSION=$(lsb_release -rs)
echo "Ubuntu Version: $UBUNTU_VERSION"

# Update System
echo "Updating system..."
sudo apt update
sudo apt upgrade -y

# Install Python 3.12 (jika belum ada)
echo "Checking Python version..."
if ! command -v python3.12 &> /dev/null; then
    echo "Installing Python 3.12..."
    
    # Untuk Ubuntu 25.10 (saat dirilis) gunakan repo default
    # Jika belum tersedia, gunakan deadsnakes PPA
    sudo apt install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt update
    sudo apt install -y python3.12 python3.12-venv python3.12-dev python3.12-distutils
else
    echo "Python 3.12 already installed"
fi

# Install Dependencies (disesuaikan untuk Ubuntu 25.10)
echo "Installing dependencies..."
sudo apt install -y wget curl git build-essential python3-pip \
libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev \
libldap2-dev libssl-dev libpq-dev libjpeg-dev libopenjp2-7-dev \
libfreetype6-dev libffi-dev libmysqlclient-dev liblcms2-dev \
libblas-dev libatlas-base-dev gfortran nodejs npm redis-server \
libgeoip-dev libmaxminddb-dev libpcre3-dev libyaml-dev \
libjpeg-turbo8-dev libwebp-dev libtiff5-dev libraqm-dev

# Install PostgreSQL 17 (atau versi terbaru)
echo "Installing PostgreSQL..."
# Cek versi PostgreSQL yang tersedia
sudo apt install -y postgresql postgresql-contrib

# Dapatkan versi PostgreSQL yang terinstall
PG_VERSION=$(ls /etc/postgresql/ | sort -V | tail -1)
echo "PostgreSQL Version: $PG_VERSION"

# Create Odoo User
echo "Creating Odoo user..."
if id "odoo" &>/dev/null; then
    echo "User odoo already exists"
else
    sudo useradd -m -d /opt/odoo -U -r -s /bin/bash odoo
fi

# Create Directories
echo "Creating directories..."
sudo mkdir -p /opt/odoo/{odoo19,venv/odoo19,custom-addons,backups}
sudo chown -R odoo:odoo /opt/odoo

# Clone Odoo 19 Source
echo "Cloning Odoo 19 source code..."
cd /opt/odoo
if [ -d "/opt/odoo/odoo19" ]; then
    echo "Odoo directory already exists, pulling latest..."
    cd /opt/odoo/odoo19
    sudo -u odoo git pull origin 19.0
else
    sudo -u odoo git clone https://github.com/odoo/odoo.git odoo19 --depth 1 --branch 19.0
fi

# Create Virtual Environment
echo "Creating virtual environment..."
cd /opt/odoo
if [ ! -d "/opt/odoo/venv/odoo19" ]; then
    sudo -u odoo python3.12 -m venv venv/odoo19
else
    echo "Virtual environment already exists"
fi

# Install Python Dependencies
echo "Installing Python dependencies..."
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install --upgrade pip setuptools wheel
sudo -u odoo /opt/odoo/venv/odoo19/bin/pip install -r /opt/odoo/odoo19/requirements.txt

# Install wkhtmltopdf untuk Ubuntu 25.10
echo "Installing wkhtmltopdf..."
# Coba beberapa sumber untuk wkhtmltopdf
if ! command -v wkhtmltopdf &> /dev/null; then
    # Coba pakai versi dari repo Ubuntu
    sudo apt install -y wkhtmltopdf || \
    # Jika tidak ada, download dari GitHub
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb && \
    sudo apt install -y ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb && \
    rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb || \
    echo "wkhtmltopdf installation failed, please install manually"
fi

# Create Odoo Configuration File
echo "Creating Odoo configuration..."
sudo tee /etc/odoo19.conf << 'EOF'
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
workers = 4
max_cron_threads = 1
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
EOF

sudo chown odoo:odoo /etc/odoo19.conf
sudo chmod 640 /etc/odoo19.conf

# Create Log Directory
sudo mkdir -p /var/log/odoo
sudo chown odoo:odoo /var/log/odoo

# Create Data Directory
sudo mkdir -p /var/lib/odoo
sudo chown odoo:odoo /var/lib/odoo

# Create PostgreSQL User
echo "Creating PostgreSQL user..."
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser --no-password odoo 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER odoo WITH PASSWORD 'odoo';" 2>/dev/null || true

# Create Systemd Service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/odoo19.service << 'EOF'
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
Restart=always
RestartSec=5
TimeoutStartSec=600
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

# Enable and Start Services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable --now odoo19

# Wait for service to start
sleep 10

# Check service status
echo "Checking Odoo service status..."
SERVICE_STATUS=$(sudo systemctl is-active odoo19)
if [ "$SERVICE_STATUS" = "active" ]; then
    echo "✅ Odoo service is running"
    
    # Get IP address
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    if [ -z "$IP_ADDRESS" ]; then
        IP_ADDRESS="localhost"
    fi
    
    echo ""
    echo "=========================================="
    echo "🎉 INSTALLATION COMPLETED SUCCESSFULLY! 🎉"
    echo "=========================================="
    echo "🌐 Odoo 19 is now running on: http://$IP_ADDRESS:8069"
    echo "🔑 Master Password: admin"
    echo ""
    echo "📊 Service Commands:"
    echo "   Check status: sudo systemctl status odoo19"
    echo "   View logs:    sudo journalctl -u odoo19 -f"
    echo "   Restart:      sudo systemctl restart odoo19"
    echo "   Stop:         sudo systemctl stop odoo19"
    echo ""
    echo "📁 Important Directories:"
    echo "   Odoo Source:    /opt/odoo/odoo19"
    echo "   Custom Addons:  /opt/odoo/custom-addons"
    echo "   Backups:        /opt/odoo/backups"
    echo "   Logs:           /var/log/odoo/"
    echo "   Config:         /etc/odoo19.conf"
    echo "=========================================="
    
    # Create monitoring script
    echo "Creating monitoring script..."
    sudo tee /opt/odoo/check_space.sh << 'EOF2'
#!/bin/bash
echo "=== Odoo Disk Usage ==="
echo "Date: $(date)"
echo "---"
df -h / /opt /var/lib/postgresql
echo "---"
echo "/opt/odoo:"
du -sh /opt/odoo/* 2>/dev/null
echo "---"
echo "PostgreSQL:"
sudo -u postgres psql -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database;" 2>/dev/null || echo "PostgreSQL not accessible"
EOF2
    
    sudo chmod +x /opt/odoo/check_space.sh
    sudo chown odoo:odoo /opt/odoo/check_space.sh
    
    echo ""
    echo "📊 Monitoring script created: /opt/odoo/check_space.sh"
    echo "Run it with: sudo -u odoo bash /opt/odoo/check_space.sh"
    
else
    echo "❌ Odoo service failed to start"
    echo "Checking logs..."
    sudo journalctl -u odoo19 --no-pager -n 20
    exit 1
fi
