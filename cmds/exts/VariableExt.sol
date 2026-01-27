// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Variable, LibVariable} from "forge-std/src/LibVariable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library VariableExt {
    using LibVariable for Variable;

    function exists(Variable memory self) internal pure returns (bool) {
        try self.assertExists() {
            return true;
        } catch {
            return false;
        }
    }

    function notExists(Variable memory self) internal pure returns (bool) {
        return !exists(self);
    }
}
