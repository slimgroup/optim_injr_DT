#!/usr/bin/env bash
# Verify all logs paths are correct

echo "=========================================="
echo "Logs Path Verification"
echo "=========================================="
echo ""

ERRORS=0

# Check optim_inject_pace.sh
echo "1. Checking optim_inject_pace.sh..."
if grep -q "#SBATCH --output=../logs/" scripts/shell/optim_inject_pace.sh && \
   grep -q "#SBATCH --error=../logs/" scripts/shell/optim_inject_pace.sh; then
  echo "   ✓ Correct (uses ../logs/ relative to scripts/)"
else
  echo "   ✗ ERROR: Wrong path"
  ((ERRORS++))
fi

# Check if logs directory exists at project root
echo ""
echo "2. Checking logs directory..."
if [ -d "logs" ]; then
  LOG_COUNT=$(ls logs/*.txt 2>/dev/null | wc -l)
  echo "   ✓ logs/ directory exists at project root (${LOG_COUNT} .txt files)"
else
  echo "   ✗ ERROR: logs/ directory not found at project root"
  ((ERRORS++))
fi

# Check if scripts/logs is empty or doesn't exist
echo ""
echo "3. Checking scripts/logs..."
if [ ! -d "scripts/logs" ] || [ -z "$(ls -A scripts/logs/*.txt 2>/dev/null)" ]; then
  echo "   ✓ scripts/logs/ is empty or doesn't exist (correct)"
else
  SCRIPTS_LOG_COUNT=$(ls scripts/logs/*.txt 2>/dev/null | wc -l)
  echo "   ⚠ WARNING: scripts/logs/ still has ${SCRIPTS_LOG_COUNT} files (should be empty)"
  ((ERRORS++))
fi

echo ""
echo "=========================================="
if [ ${ERRORS} -eq 0 ]; then
  echo "✓ All checks passed!"
else
  echo "✗ Found ${ERRORS} issue(s)"
fi
echo "=========================================="
