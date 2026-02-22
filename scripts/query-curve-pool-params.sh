#!/usr/bin/env bash
set -euo pipefail

POOL="${1:?Usage: query-curve-pool.sh <pool-address>}"

query() { cast call "$POOL" "$1"; }

name_raw=$(query "name()(string)")
symbol_raw=$(query "symbol()(string)")
A=$(query "A()(uint256)")
fee=$(query "fee()(uint256)")
offpeg=$(query "offpeg_fee_multiplier()(uint256)")
ma_exp=$(query "ma_exp_time()(uint256)")

# echo "name:                   $name_raw"
# echo "symbol:                 $symbol_raw"
# echo "A:                      $A"
# echo "fee:                    $fee"
# echo "offpeg_fee_multiplier:  $offpeg"
# echo "ma_exp_time:            $ma_exp"

echo $name_raw 
echo $symbol_raw
echo $A
echo $fee
echo $offpeg
echo $ma_exp