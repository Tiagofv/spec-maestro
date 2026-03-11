#!/bin/bash
#
# Create Research Artifact Script
# Generates a research artifact file from query input
#
# Usage: ./create-research.sh "Research query string"
#
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Directory paths
RESEARCH_DIR="${PROJECT_ROOT}/.maestro/research"
TEMPLATE_FILE="${PROJECT_ROOT}/.maestro/templates/research-template.md"

# Check arguments
if [ $# -lt 1 ]; then
    echo "Error: Research query is required" >&2
    echo "Usage: $0 \"Research query string\"" >&2
    exit 1
fi

QUERY="$1"

# Validate template exists
if [ ! -f "${TEMPLATE_FILE}" ]; then
    echo "Error: Research template not found at ${TEMPLATE_FILE}" >&2
    exit 1
fi

# Ensure research directory exists
if [ ! -d "${RESEARCH_DIR}" ]; then
    mkdir -p "${RESEARCH_DIR}" || {
        echo "Error: Failed to create research directory ${RESEARCH_DIR}" >&2
        exit 1
    }
fi

# Generate slug from query
# Convert to lowercase, replace non-alphanumeric with dashes, collapse multiple dashes
SLUG=$(echo "${QUERY}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

# Truncate to max 50 chars (leave room for date prefix)
if [ ${#SLUG} -gt 50 ]; then
    SLUG="${SLUG:0:50}"
    # Remove trailing dash if present after truncation
    SLUG=$(echo "${SLUG}" | sed 's/-$//')
fi

# Ensure slug is not empty
if [ -z "${SLUG}" ]; then
    SLUG="research"
fi

# Generate date-based filename
DATE_PREFIX=$(date +%Y%m%d)
FILENAME="${DATE_PREFIX}-${SLUG}.md"
FILEPATH="${RESEARCH_DIR}/${FILENAME}"

# Check if file already exists
if [ -f "${FILEPATH}" ]; then
    echo "Error: Research file already exists: ${FILEPATH}" >&2
    exit 1
fi

# Get current date info
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AUTHOR="${USER:-$(whoami 2>/dev/null || echo 'unknown')}"

# Read template and populate frontmatter
if ! TEMPLATE_CONTENT=$(cat "${TEMPLATE_FILE}" 2>/dev/null); then
    echo "Error: Failed to read template file" >&2
    exit 1
fi

# Replace placeholders in template
RESEARCH_CONTENT="${TEMPLATE_CONTENT}"
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/{Research Title}/${QUERY}/g")
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/{Original research query}/${QUERY}/g")
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/{ISO timestamp}/${CURRENT_ISO}/g")
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/{author}/${AUTHOR}/g")
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/{Query Title}/${QUERY}/g")
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/YYYYMMDD-${SLUG}/${DATE_PREFIX}-${SLUG}/g")
RESEARCH_CONTENT=$(echo "${RESEARCH_CONTENT}" | sed "s/YYYY-MM-DD/${CURRENT_DATE}/g")

# Write the research file
if ! echo "${RESEARCH_CONTENT}" > "${FILEPATH}" 2>/dev/null; then
    echo "Error: Failed to write research file ${FILEPATH}" >&2
    exit 1
fi

# Output the created file path for the caller
echo "${FILEPATH}"
