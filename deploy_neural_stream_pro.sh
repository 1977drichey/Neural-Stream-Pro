#!/bin/bash

# 🚀 NEURAL STREAM PRO - COMPLETE DEPLOYMENT SCRIPT 🚀
# Advanced Pi Zero 2W streaming solution with recording, time-lapse, and NAS integration
# Version: 3.0 Pro
# Run as: sudo ./deploy_neural_stream_pro.sh

set -e

# Configuration
PI_IP=$(hostname -I | awk '{print $1}')
INSTALL_DIR="/opt/neural-stream"
WEB_DIR="/var/www/neural-stream"
DATA_DIR="/var/lib/neural-stream"
LOG_DIR="/var/log/neural-stream"
CERT_DIR="/etc/ssl/neural-stream"
SERVICE_USER="pi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║        🚀 NEURAL STREAM PRO DEPLOYMENT 🚀           ║"
    echo "║                                                      ║"
    echo "║  Advanced Pi Camera Streaming & Recording Solution   ║"
    echo "║                   Version 3.0 Pro                   ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_step() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"
}

check_requirements() {
    log_step "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check Pi model
    PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "Unknown")
    log_step "Detected: $PI_MODEL"
    
    # Check if camera is connected
    if ! libcamera-hello --list-cameras &>/dev/null; then
        log_warning "No camera detected. Please connect camera and enable it in raspi-config"
    fi
    
    # Check available space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 2000000 ]]; then
        log_warning "Low disk space detected. Consider expanding filesystem"
    fi
}

create_directories() {
    log_step "Creating directory structure..."
    
    mkdir -p $INSTALL_DIR/{bin,config,scripts,data}
    mkdir -p $WEB_DIR/{css,js,uploads,recordings,timelapse}
    mkdir -p $DATA_DIR/{recordings,timelapse,snapshots,config}
    mkdir -p $LOG_DIR
    mkdir -p $CERT_DIR
    
    # Set permissions
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR $DATA_DIR
    chown -R www-data:www-data $WEB_DIR
    chmod 755 $LOG_DIR
}

install_dependencies() {
    log_step "Installing system dependencies..."
    
    # Update system
    apt update && apt upgrade -y
    
    # Install packages
    apt install -y \
        nginx python3 python3-pip python3-venv \
        curl wget unzip jq git \
        ffmpeg v4l-utils \
        openssl ca-certificates \
        rsync rclone \
        systemd-timesyncd \
        logrotate fail2ban \
        htop iotop
    
    # Install Python packages in virtual environment
    log_step "Setting up Python virtual environment..."
    python3 -m venv $INSTALL_DIR/venv
    source $INSTALL_DIR/venv/bin/activate
    
    pip install --upgrade pip
    pip install \
        flask flask-cors \
        psutil schedule \
        paho-mqtt \
        python-dotenv \
        watchdog \
        requests \
        pillow
}

install_go2rtc() {
    log_step "Installing go2rtc..."
    
    cd $INSTALL_DIR/bin
    
    # Detect architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]]; then
        GO2RTC_ARCH="arm64"
    elif [[ "$ARCH" == "armv7l" ]]; then
        GO2RTC_ARCH="arm"
    else
        GO2RTC_ARCH="arm64"  # Default for Pi Zero 2W
    fi
    
    wget -O go2rtc "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_${GO2RTC_ARCH}"
    chmod +x go2rtc
    
    # Create go2rtc config
    cat > $INSTALL_DIR/config/go2rtc.yaml << 'EOF'
api:
  origin: '*'
  listen: ":1984"

log:
  format: text
  level: info
  output: /var/log/neural-stream/go2rtc.log

rtsp:
  default_query: mp4

streams:
  neural_pi_cam:
    - exec:libcamera-vid -t 0 --inline --codec h264 -o - --width 1280 --height 720 --framerate 15
  neural_tcp_stream:
    - tcp://127.0.0.1:8888
  neural_hq_stream:
    - exec:libcamera-vid -t 0 --inline --codec h264 -o - --width 1920 --height 1080 --framerate 10

web
