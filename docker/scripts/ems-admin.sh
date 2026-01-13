#!/bin/sh

# EMS Admin Script - Processes and executes EMS object creation scripts
# This script reads all .ems and .bridge files from /scripts/destination/
# and executes them using tibemsadmin in alphabetical order

set -e

# Configuration
EMS_SERVER="${EMSSERVERNAME:-emsserver-svc}"
EMS_PORT="${EMS_PORT:-7222}"
EMS_USER="${EMS_USER:-admin}"
SCRIPT_DIR="/scripts/destination"
TEMP_LIST="/tmp/ems-scripts.list"
TIBCO_HOME="${TIBCO_HOME:-/opt/tibco}"
EMS_VERSION="${EMS_VERSION:-10.4}"
TIBEMSADMIN="${TIBCO_HOME}/ems/${EMS_VERSION}/bin/tibemsadmin"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "TIBCO EMS Objects Creation Job"
echo "=========================================="
echo "EMS Server: ${EMS_SERVER}:${EMS_PORT}"
echo "EMS User: ${EMS_USER}"
echo "Script Directory: ${SCRIPT_DIR}"
echo "=========================================="

# Check if tibemsadmin exists
if [ ! -f "${TIBEMSADMIN}" ]; then
    echo "${RED}ERROR: tibemsadmin not found at ${TIBEMSADMIN}${NC}"
    echo "Please ensure EMS client binaries are properly copied to the image"
    exit 1
fi

# Check if script directory exists and has files
if [ ! -d "${SCRIPT_DIR}" ]; then
    echo "${RED}ERROR: Script directory ${SCRIPT_DIR} does not exist${NC}"
    exit 1
fi

# List all script files
ls -1 "${SCRIPT_DIR}" > "${TEMP_LIST}"

# Count files
TOTAL_FILES=$(wc -l < "${TEMP_LIST}")

if [ "${TOTAL_FILES}" -eq 0 ]; then
    echo "${YELLOW}WARNING: No EMS script files found in ${SCRIPT_DIR}${NC}"
    echo "Job completed with no actions taken"
    exit 0
fi

echo ""
echo "Found ${TOTAL_FILES} script file(s) to process:"
cat "${TEMP_LIST}" | while read LINE; do
    echo "  - ${LINE}"
done
echo ""

# Process each script file
COUNTER=0
SUCCESS=0
FAILED=0

while read LINE; do
    COUNTER=$((COUNTER + 1))
    SCRIPT_PATH="${SCRIPT_DIR}/${LINE}"
    
    echo "----------------------------------------"
    echo "[${COUNTER}/${TOTAL_FILES}] Processing: ${LINE}"
    echo "----------------------------------------"
    
    # Check if file exists
    if [ ! -f "${SCRIPT_PATH}" ]; then
        echo "${RED}ERROR: File not found: ${SCRIPT_PATH}${NC}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Display file content (first 5 lines for preview)
    echo "Preview (first 5 lines):"
    head -n 5 "${SCRIPT_PATH}" | sed 's/^/  | /'
    echo ""
    
    # Execute the EMS script
    echo "Executing: tibemsadmin -server ${EMS_SERVER}:${EMS_PORT} -user ${EMS_USER} -script ${SCRIPT_PATH}"
    
    if ${TIBEMSADMIN} -server ${EMS_SERVER}:${EMS_PORT} -ignore -user ${EMS_USER} -script "${SCRIPT_PATH}"; then
        echo "${GREEN}✓ Successfully processed: ${LINE}${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "${RED}✗ Failed to process: ${LINE}${NC}"
        FAILED=$((FAILED + 1))
    fi
    
    echo ""
    
done < "${TEMP_LIST}"

# Summary
echo "=========================================="
echo "Job Completion Summary"
echo "=========================================="
echo "Total scripts: ${TOTAL_FILES}"
echo "${GREEN}Successful: ${SUCCESS}${NC}"
if [ ${FAILED} -gt 0 ]; then
    echo "${RED}Failed: ${FAILED}${NC}"
else
    echo "Failed: ${FAILED}"
fi
echo "=========================================="

if [ ${FAILED} -gt 0 ]; then
    echo "${YELLOW}WARNING: Some scripts failed. Check logs above for details.${NC}"
    echo "Note: Failures on existing objects are expected and ignored (using -ignore flag)"
fi

echo ""
echo "${GREEN}EMS Objects Creation Job Completed${NC}"
echo ""

# Exit with success even if some scripts failed (due to -ignore flag)
exit 0
