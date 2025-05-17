#!/bin/bash
#
# HoRNDIS USB Tethering Helper Script
# This script helps install, uninstall, and manage the HoRNDIS kernel extension
# for Android USB tethering on macOS.
#
# Based on the HoRNDIS project: https://github.com/jwise/HoRNDIS
#

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script variables
KEXT_NAME="HoRNDIS.kext"
KEXT_BUNDLE_ID="com.joshuawise.kexts.HoRNDIS"
KEXT_PATHS=(
    "/Library/Extensions/${KEXT_NAME}"
    "/System/Library/Extensions/${KEXT_NAME}"
)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="${SCRIPT_DIR}"
BUILD_DIR="${REPO_DIR}/build"
RELEASE_KEXT="${BUILD_DIR}/Release/${KEXT_NAME}"
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR_VERSION=$(echo "${MACOS_VERSION}" | cut -d. -f1)
MACOS_MINOR_VERSION=$(echo "${MACOS_VERSION}" | cut -d. -f2)

# Check if running with sudo/root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script must be run with sudo or as root.${NC}"
        exit 1
    fi
}

# Print script header
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    HoRNDIS USB Tethering Helper        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "macOS Version: ${MACOS_VERSION}"
    echo ""
}

# Check macOS version compatibility
check_macos_version() {
    # HoRNDIS is designed for macOS 10.11+
    if [ "${MACOS_MAJOR_VERSION}" -lt 10 ] || ([ "${MACOS_MAJOR_VERSION}" -eq 10 ] && [ "${MACOS_MINOR_VERSION}" -lt 11 ]); then
        echo -e "${RED}This version of HoRNDIS requires macOS 10.11 or newer.${NC}"
        exit 1
    fi
    
    # Warn about newer macOS versions that might have compatibility issues
    if [ "${MACOS_MAJOR_VERSION}" -gt 12 ]; then
        echo -e "${YELLOW}Warning: You're running macOS ${MACOS_VERSION}.${NC}"
        echo -e "${YELLOW}HoRNDIS may have compatibility issues with newer macOS versions.${NC}"
        echo -e "${YELLOW}Proceed at your own risk.${NC}\n"
    fi
}

# Check if Xcode is installed
check_xcode() {
    if ! xcode-select -p &>/dev/null; then
        echo -e "${RED}Xcode or Xcode Command Line Tools are not installed.${NC}"
        echo -e "${YELLOW}Please install them using: xcode-select --install${NC}"
        exit 1
    fi
}

# Build the kernel extension from source
build_kext() {
    echo -e "${BLUE}Building HoRNDIS kernel extension...${NC}"
    
    # Make sure the build directory exists
    mkdir -p "${BUILD_DIR}"
    
    # Navigate to repo dir and build
    cd "${REPO_DIR}"
    
    if ! xcodebuild -project HoRNDIS.xcodeproj; then
        echo -e "${RED}Failed to build HoRNDIS kernel extension.${NC}"
        exit 1
    fi
    
    if [ ! -d "${RELEASE_KEXT}" ]; then
        echo -e "${RED}Build completed but kernel extension not found at ${RELEASE_KEXT}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully built HoRNDIS kernel extension.${NC}"
}

# Check if SIP (System Integrity Protection) is enabled
check_sip() {
    sip_status=$(csrutil status | grep -i "System Integrity Protection status:")
    
    if echo "${sip_status}" | grep -q "enabled"; then
        echo -e "${YELLOW}System Integrity Protection (SIP) is enabled.${NC}"
        
        # For macOS 10.13 (High Sierra) and newer, SIP affects kext loading
        if [ "${MACOS_MAJOR_VERSION}" -gt 10 ] || ([ "${MACOS_MAJOR_VERSION}" -eq 10 ] && [ "${MACOS_MINOR_VERSION}" -ge 13 ]); then
            echo -e "${YELLOW}On macOS 10.13+, you may need to approve the kernel extension in System Preferences.${NC}"
            echo -e "${YELLOW}After installation, if prompted, go to System Preferences > Security & Privacy to approve.${NC}"
        fi
    else
        echo -e "${GREEN}System Integrity Protection (SIP) is disabled.${NC}"
    fi
}

# Install the kernel extension
install_kext() {
    echo -e "${BLUE}Installing HoRNDIS kernel extension...${NC}"
    
    # Ensure the kext exists
    if [ ! -d "${RELEASE_KEXT}" ]; then
        echo -e "${RED}Kernel extension not found at ${RELEASE_KEXT}${NC}"
        echo -e "${YELLOW}Please build the kernel extension first.${NC}"
        exit 1
    fi
    
    # Copy to /Library/Extensions
    echo "Copying ${KEXT_NAME} to /Library/Extensions..."
    cp -R "${RELEASE_KEXT}" /Library/Extensions/
    
    # Set ownership and permissions
    chown -R root:wheel "/Library/Extensions/${KEXT_NAME}"
    chmod -R 755 "/Library/Extensions/${KEXT_NAME}"
    
    # Update system caches
    echo "Updating system extension cache..."
    touch /Library/Extensions
    touch /System/Library/Extensions
    
    if [ "${MACOS_MAJOR_VERSION}" -eq 10 ] && [ "${MACOS_MINOR_VERSION}" -lt 13 ]; then
        # For macOS 10.11 and 10.12
        kextcache -i /
    else
        # For macOS 10.13+ (High Sierra and newer)
        kextcache -system-prelinked-kernel
        kextcache -system-caches
    fi
    
    echo -e "${GREEN}Kernel extension installed.${NC}"
    echo -e "${YELLOW}You may need to restart your computer for changes to take effect.${NC}"
    
    # For macOS 10.13+ (High Sierra and newer)
    if [ "${MACOS_MAJOR_VERSION}" -gt 10 ] || ([ "${MACOS_MAJOR_VERSION}" -eq 10 ] && [ "${MACOS_MINOR_VERSION}" -ge 13 ]); then
        echo -e "${YELLOW}Important: On macOS 10.13+, you need to approve the kernel extension in System Preferences.${NC}"
        echo -e "${YELLOW}Go to System Preferences > Security & Privacy to approve.${NC}"
    fi
}

# Load the kernel extension
load_kext() {
    echo -e "${BLUE}Loading HoRNDIS kernel extension...${NC}"
    
    # Check if already loaded
    if kextstat | grep -q "${KEXT_BUNDLE_ID}"; then
        echo -e "${YELLOW}HoRNDIS kernel extension is already loaded.${NC}"
        return 0
    fi
    
    # Try to load the kext
    if kextload "/Library/Extensions/${KEXT_NAME}"; then
        echo -e "${GREEN}Successfully loaded HoRNDIS kernel extension.${NC}"
    else
        echo -e "${RED}Failed to load HoRNDIS kernel extension.${NC}"
        echo -e "${YELLOW}You may need to restart your computer, or approve the extension in System Preferences.${NC}"
    fi
}

# Unload the kernel extension
unload_kext() {
    echo -e "${BLUE}Unloading HoRNDIS kernel extension...${NC}"
    
    # Check if loaded
    if ! kextstat | grep -q "${KEXT_BUNDLE_ID}"; then
        echo -e "${YELLOW}HoRNDIS kernel extension is not currently loaded.${NC}"
        return 0
    fi
    
    # Try to unload the kext
    if kextunload -b "${KEXT_BUNDLE_ID}"; then
        echo -e "${GREEN}Successfully unloaded HoRNDIS kernel extension.${NC}"
    else
        echo -e "${RED}Failed to unload HoRNDIS kernel extension.${NC}"
        echo -e "${YELLOW}The kernel extension might be in use. You may need to disconnect your Android device first.${NC}"
    fi
}

# Uninstall the kernel extension
uninstall_kext() {
    echo -e "${BLUE}Uninstalling HoRNDIS kernel extension...${NC}"
    
    # First try to unload
    unload_kext
    
    # Remove the kext files
    for kext_path in "${KEXT_PATHS[@]}"; do
        if [ -d "${kext_path}" ]; then
            echo "Removing ${kext_path}..."
            rm -rf "${kext_path}"
        fi
    done
    
    # Update system caches
    echo "Updating system extension cache..."
    touch /Library/Extensions
    touch /System/Library/Extensions
    
    if [ "${MACOS_MAJOR_VERSION}" -eq 10 ] && [ "${MACOS_MINOR_VERSION}" -lt 13 ]; then
        # For macOS 10.11 and 10.12
        kextcache -i /
    else
        # For macOS 10.13+ (High Sierra and newer)
        kextcache -system-prelinked-kernel
        kextcache -system-caches
    fi
    
    echo -e "${GREEN}HoRNDIS kernel extension uninstalled.${NC}"
    echo -e "${YELLOW}You may need to restart your computer for changes to take effect.${NC}"
}

# Check status of the kernel extension
check_status() {
    echo -e "${BLUE}Checking HoRNDIS status...${NC}"
    
    # Check if files exist
    echo "Checking installation locations:"
    for kext_path in "${KEXT_PATHS[@]}"; do
        if [ -d "${kext_path}" ]; then
            echo -e "  ${GREEN}Found${NC}: ${kext_path}"
        else
            echo -e "  ${RED}Not found${NC}: ${kext_path}"
        fi
    done
    
    # Check if loaded
    echo ""
    echo "Checking kernel extension status:"
    if kextstat | grep -q "${KEXT_BUNDLE_ID}"; then
        kext_info=$(kextstat | grep "${KEXT_BUNDLE_ID}")
        echo -e "  ${GREEN}Loaded${NC}: ${kext_info}"
    else
        echo -e "  ${RED}Not loaded${NC}"
    fi
    
    # Check network interfaces
    echo ""
    echo "Checking for RNDIS network interfaces:"
    if ifconfig | grep -A 1 "POINTOPOINT" | grep -q "inet"; then
        echo -e "  ${GREEN}Found active tethering interface${NC}:"
        ifconfig | grep -A 2 "POINTOPOINT" | grep -v "POINTOPOINT" | grep -v "^$"
    else
        echo -e "  ${RED}No active tethering interface found${NC}"
    fi
}

# Show usage help
show_help() {
    echo "Usage: sudo $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  build      Build the kernel extension from source"
    echo "  install    Install the kernel extension"
    echo "  load       Load the kernel extension"
    echo "  unload     Unload the kernel extension"
    echo "  uninstall  Uninstall the kernel extension"
    echo "  status     Check status of the kernel extension"
    echo "  help       Show this help message"
    echo ""
}

# Show tethering guide
show_tethering_guide() {
    echo -e "${BLUE}=== Android USB Tethering Guide ===${NC}"
    echo ""
    echo -e "To enable USB tethering on your Android device:"
    echo ""
    echo -e "1. Connect your Android phone to your Mac using a USB cable"
    echo -e "2. On your Android device, go to:"
    echo -e "   ${YELLOW}Settings > Network & Internet > Hotspot & tethering${NC}"
    echo -e "   (Menu location may vary depending on Android version and device manufacturer)"
    echo -e "3. Turn on ${YELLOW}USB tethering${NC}"
    echo -e "4. Your Mac should detect the device and create a new network interface"
    echo ""
    echo -e "To verify the connection:"
    echo -e "1. Check your network settings or run ${YELLOW}ifconfig${NC} in Terminal"
    echo -e "2. Try to browse the web or ping a website"
    echo ""
    echo -e "Troubleshooting tips:"
    echo -e "- Make sure the HoRNDIS kernel extension is loaded"
    echo -e "- Try disconnecting and reconnecting your Android device"
    echo -e "- On newer macOS versions, ensure the kernel extension is approved in System Preferences"
    echo -e "- Restart your Mac if other steps don't work"
    echo ""
}

# Main script logic
main() {
    print_header
    check_macos_version
    
    case "$1" in
        build)
            check_root
            check_xcode
            build_kext
            ;;
        install)
            check_root
            check_sip
            install_kext
            show_tethering_guide
            ;;
        load)
            check_root
            load_kext
            ;;
        unload)
            check_root
            unload_kext
            ;;
        uninstall)
            check_root
            uninstall_kext
            ;;
        status)
            check_root
            check_status
            ;;
        guide)
            show_tethering_guide
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${YELLOW}No option specified. Showing help:${NC}\n"
            show_help
            ;;
    esac
}

# Run the main function with all arguments
main "$@"