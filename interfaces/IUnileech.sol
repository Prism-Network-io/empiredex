// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./IEmpirePair.sol";

interface IUnileech {
    function leech(
        IEmpirePair pair,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external;
}
