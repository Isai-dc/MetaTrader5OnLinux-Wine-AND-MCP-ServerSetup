#!/bin/bash
# MetaTrader5 Python Setup Script for Existing Wine Prefix
# This script sets up Python and dependencies in an existing MT5 Wine prefix

set -e

# Configuration - Modify these paths as needed
TARGET_PREFIX="${1:-$HOME/.mt5}"
MCP_SERVER_DIR="${2:-$HOME/mcp-metatrader5-server}"  # Change this to your cloned repo path

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root"
    exit 1
fi

# Check target prefix exists
if [[ ! -d "$TARGET_PREFIX" ]]; then
    log_error "Target Wine prefix not found: $TARGET_PREFIX"
    exit 1
fi

# Check MCP server directory exists
if [[ ! -d "$MCP_SERVER_DIR" ]]; then
    log_error "MCP server directory not found: $MCP_SERVER_DIR"
    exit 1
fi

log_info "Setting up Python for MetaTrader5 MCP Server"
log_info "============================================="
log_info "Target prefix: $TARGET_PREFIX"
log_info "MCP server dir: $MCP_SERVER_DIR"
log_info ""

# Step 1: Check Wine installation
log_info "Step 1: Checking Wine installation..."
if ! command -v wine > /dev/null 2>&1; then
    log_error "Wine not found. Please install Wine first."
    exit 1
fi
log_success "Wine found: $(wine --version)"

# Step 2: Check MetaTrader5 installation
log_info "Step 2: Checking MetaTrader5 installation..."
if [[ ! -f "$TARGET_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]]; then
    log_error "MetaTrader5 not found in target prefix"
    log_error "Expected: $TARGET_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
    exit 1
fi
log_success "MetaTrader5 found in target prefix"

# Step 3: Install Python in Wine (if not already installed)
log_info "Step 3: Checking/Installing Python in Wine..."
if [[ ! -f "$TARGET_PREFIX/drive_c/Program Files/Python312/python.exe" ]]; then
    log_warning "Python 3.12 not found in Wine prefix"
    log_info "Downloading Python 3.12 installer..."

    # Download Python 3.12 installer
    PYTHON_URL="https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
    PYTHON_INSTALLER="/tmp/python-3.12.0-amd64.exe"

    if ! wget -q "$PYTHON_URL" -O "$PYTHON_INSTALLER"; then
        log_error "Failed to download Python installer"
        exit 1
    fi

    log_info "Installing Python 3.12 in Wine..."
    if ! WINEPREFIX="$TARGET_PREFIX" wine "$PYTHON_INSTALLER" /quiet InstallAllUsers=1 PrependPath=1 2>/dev/null; then
        log_error "Python installation failed"
        rm -f "$PYTHON_INSTALLER"
        exit 1
    fi

    rm -f "$PYTHON_INSTALLER"
    log_success "Python 3.12 installed in Wine"
else
    log_success "Python 3.12 already installed in Wine"
fi

# Step 4: Verify Python works
log_info "Step 4: Verifying Python works in Wine..."
if ! WINEPREFIX="$TARGET_PREFIX" wine python --version > /dev/null 2>&1; then
    log_error "Python not working in Wine prefix"
    exit 1
fi
PYTHON_VERSION=$(WINEPREFIX="$TARGET_PREFIX" wine python --version 2>/dev/null)
log_success "Python working: $PYTHON_VERSION"

# Step 5: Upgrade pip
log_info "Step 5: Upgrading pip..."
if ! WINEPREFIX="$TARGET_PREFIX" wine python -m pip install --upgrade pip > /dev/null 2>&1; then
    log_warning "Failed to upgrade pip, continuing anyway..."
fi
PIP_VERSION=$(WINEPREFIX="$TARGET_PREFIX" wine python -m pip --version 2>/dev/null | cut -d' ' -f2)
log_success "pip version: $PIP_VERSION"

# Step 6: Install Python dependencies
log_info "Step 6: Installing Python dependencies..."
cd "$MCP_SERVER_DIR"

# Extract dependencies from pyproject.toml or use hardcoded list
DEPENDENCIES=(
    "fastmcp==2.14.0"
    "metatrader5==5.0.5430"
    "pandas>=2.3.3"
    "pydantic>=2.11.9"
    "python-dotenv>=1.1.1"
)

log_info "Installing ${#DEPENDENCIES[@]} dependencies..."

for dep in "${DEPENDENCIES[@]}"; do
    log_info "Installing: $dep"
    if ! WINEPREFIX="$TARGET_PREFIX" wine python -m pip install "$dep" > /dev/null 2>&1; then
        log_warning "Failed to install $dep, trying with --user flag..."
        if ! WINEPREFIX="$TARGET_PREFIX" wine python -m pip install --user "$dep" > /dev/null 2>&1; then
            log_error "Failed to install $dep even with --user flag"
            log_info "Trying without version constraints..."
            # Extract package name without version
            PKG_NAME=$(echo "$dep" | sed 's/[<=>].*//')
            WINEPREFIX="$TARGET_PREFIX" wine python -m pip install "$PKG_NAME"
        fi
    fi
done
log_success "Python dependencies installed"

# Step 7: Test MetaTrader5 Python module
log_info "Step 7: Testing MetaTrader5 Python module..."
if ! WINEPREFIX="$TARGET_PREFIX" wine python -c "import MetaTrader5; print('MetaTrader5 version:', MetaTrader5.__version__)" 2>/dev/null; then
    log_error "MetaTrader5 Python module not working"
    log_info "Trying to install metatrader5 package explicitly..."
    WINEPREFIX="$TARGET_PREFIX" wine python -m pip install metatrader5

    # Test again
    if ! WINEPREFIX="$TARGET_PREFIX" wine python -c "import MetaTrader5; print('MetaTrader5 version:', MetaTrader5.__version__)" 2>/dev/null; then
        log_error "MetaTrader5 module still not working after reinstall"
        exit 1
    fi
fi
MT5_VERSION=$(WINEPREFIX="$TARGET_PREFIX" wine python -c "import MetaTrader5; print(MetaTrader5.__version__)" 2>/dev/null)
log_success "MetaTrader5 Python module working: version $MT5_VERSION"

# Step 8: Test MCP server import
log_info "Step 8: Testing MCP server import..."
if ! WINEPREFIX="$TARGET_PREFIX" wine python -c "
import sys
sys.path.insert(0, 'Z:$MCP_SERVER_DIR/src')
from mcp_mt5 import main
print('MCP server import successful')
" 2>/dev/null; then
    log_error "MCP server import failed"
    log_info "Checking MCP server directory structure..."
    ls -la "$MCP_SERVER_DIR/src/" || echo "src/ directory not found"
    exit 1
fi
log_success "MCP server import successful"

# Step 9: Test MetaTrader5 connection
log_info "Step 9: Testing MetaTrader5 connection..."
if ! WINEPREFIX="$TARGET_PREFIX" wine python -c "
import MetaTrader5 as mt5
import os

# Try to initialize
mt5_path = os.path.join('C:\\\\\\\\', 'Program Files', 'MetaTrader 5', 'terminal64.exe')
initialized = mt5.initialize(path=mt5_path)

if initialized:
    print('MT5 initialized successfully')
    print('Version:', mt5.version())

    # Try to get account info
    account = mt5.account_info()
    if account:
        print('Account login:', account.login)
        print('Server:', account.server)
        print('Balance:', account.balance)
    else:
        print('No account info (might not be logged in)')

    mt5.shutdown()
else:
    print('MT5 initialization failed:', mt5.last_error())
" 2>&1 | grep -q "MT5 initialized successfully"; then
    log_success "MetaTrader5 connection test successful"
else
    log_warning "MetaTrader5 connection test had issues (might need to be logged in)"
    WINEPREFIX="$TARGET_PREFIX" wine python -c "
import MetaTrader5 as mt5
import os
mt5_path = os.path.join('C:\\\\\\\\', 'Program Files', 'MetaTrader 5', 'terminal64.exe')
initialized = mt5.initialize(path=mt5_path)
print('Initialized:', initialized)
if not initialized:
    print('Error:', mt5.last_error())
" 2>&1 | tail -5
fi

# Step 10: Create MCP configuration
log_info "Step 10: Creating MCP configuration..."
MCP_CONFIG_DIR="$(dirname "$TARGET_PREFIX")"
MCP_CONFIG_FILE="$MCP_CONFIG_DIR/.mcp.json"

cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "metatrader5": {
      "command": "bash",
      "args": [
        "-c",
        "WINEPREFIX=$TARGET_PREFIX wine python -c \\\"import sys; sys.path.insert(0, 'Z:$MCP_SERVER_DIR/src'); import os; os.chdir('Z:$MCP_SERVER_DIR'); from mcp_mt5 import main; main()\\\""
      ],
      "env": {
        "MT5_PATH": "C:\\\\\\\\Program Files\\\\\\\\MetaTrader 5\\\\\\\\terminal64.exe"
      },
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
EOF

log_success "MCP configuration created: $MCP_CONFIG_FILE"

# Step 11: Create setup summary
log_info "Step 11: Creating setup summary..."
cat > "$MCP_CONFIG_DIR/mt5_python_setup_summary.txt" << EOF
MetaTrader5 Python Setup Summary
===============================
Date: $(date)
Target Prefix: $TARGET_PREFIX
MCP Server Dir: $MCP_SERVER_DIR

Installation Details:
- Python: $(WINEPREFIX="$TARGET_PREFIX" wine python --version 2>/dev/null)
- pip: $(WINEPREFIX="$TARGET_PREFIX" wine python -m pip --version 2>/dev/null | cut -d' ' -f2)
- MetaTrader5 module: $MT5_VERSION

Installed Packages:
$(WINEPREFIX="$TARGET_PREFIX" wine python -m pip list 2>/dev/null | grep -E "(fastmcp|metatrader5|pandas|pydantic|python-dotenv)")

File Locations:
- Wine prefix: $TARGET_PREFIX
- MetaTrader5: $TARGET_PREFIX/drive_c/Program Files/MetaTrader 5/
- Python: $TARGET_PREFIX/drive_c/Program Files/Python312/
- MCP config: $MCP_CONFIG_FILE

Test Commands:
1. Test Python: WINEPREFIX="$TARGET_PREFIX" wine python --version
2. Test MetaTrader5: WINEPREFIX="$TARGET_PREFIX" wine python -c "import MetaTrader5; print(MetaTrader5.__version__)"
3. Test MCP server: WINEPREFIX="$TARGET_PREFIX" wine python -c "import sys; sys.path.insert(0, 'Z:$MCP_SERVER_DIR/src'); from mcp_mt5 import main; print('OK')"
4. Test MT5 connection: WINEPREFIX="$TARGET_PREFIX" wine python -c "import MetaTrader5 as mt5; mt5.initialize(); print(mt5.version()); mt5.shutdown()"

MCP Server Command:
bash -c "WINEPREFIX=$TARGET_PREFIX wine python -c \\\"import sys; sys.path.insert(0, 'Z:$MCP_SERVER_DIR/src'); import os; os.chdir('Z:$MCP_SERVER_DIR'); from mcp_mt5 import main; main()\\\""

Next Steps:
1. Ensure MetaTrader5 terminal is running in Wine
2. Copy the MCP config to Claude Code configuration directory
3. Restart Claude Code to load the MCP server
4. Test with: mcp__metatrader5__initialize
EOF

log_success "Setup summary created: $MCP_CONFIG_DIR/mt5_python_setup_summary.txt"

log_info ""
log_info "============================================="
log_success "MetaTrader5 Python setup completed successfully!"
log_info "============================================="
log_info ""
log_info "Summary:"
log_info "- Python installed/verified in Wine prefix"
log_info "- All dependencies installed"
log_info "- MetaTrader5 Python module working"
log_info "- MCP server import successful"
log_info "- MCP configuration generated"
log_info ""
log_info "Next steps:"
log_info "1. Ensure MetaTrader5 terminal is running in Wine"
log_info "2. Copy MCP config to Claude Code: $MCP_CONFIG_FILE"
log_info "3. Restart Claude Code"
log_info "4. Test with: mcp__metatrader5__initialize"
log_info ""
log_info "Setup summary: $MCP_CONFIG_DIR/mt5_python_setup_summary.txt"
