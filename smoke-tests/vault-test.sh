#!/bin/bash
# Smoke tests in order to check vault status, and make sure reads/writes/deletes work
RED="\033[0;31m"

GREEN="\033[0;32m"
DEFAULT="\033[0m"
echo ""

FAILED=0
SUCCESS=0

echo Testing Vault:

export VAULT_SKIP_VERIFY=true

# Check if vault is running
echo -e "\nTesting vault status"
PASSED=true
vault status || PASSED=false
if [ "$PASSED" == true ]; then
	echo -e "${GREEN}Test Successful.${DEFAULT}"
	((SUCCESS++))
else
	echo -e "${RED}Test Failed.${DEFAULT}"
	((FAILED++))
fi

# Write and read a credential from vault
echo -e "\nTesting vault read/writes:"
PASSED=true
vault write secret/test foo=bar || PASSED=false
vault read secret/test || PASSED=false
if [ "$PASSED" == true ]; then
	echo -e "${GREEN}Test Successful.${DEFAULT}"
	((SUCCESS++))
else
	echo -e "${RED}Test Failed.${DEFAULT}"
	((FAILED++))
fi

# Delete credential from vault and verify
echo -e "\nTesting vault deletes"
PASSED=true
vault delete secret/test || PASSED=false
vault read secret/test && PASSED=false 
if [ "$PASSED" == true ]; then
	echo -e "${GREEN}Test Successful.${DEFAULT}"
	((SUCCESS++))
else
	echo -e "${RED}Test Failed.${DEFAULT}"
	((FAILED++))
fi

echo ""
# Print results of tests 
if [ $FAILED == 0 ]; then
  echo -e ${GREEN}
else
  echo -e ${RED}
fi
echo -e $SUCCESS / $(($SUCCESS+$FAILED)) tests passed.${DEFAULT}
