// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IUnileech.sol";
import "../interfaces/IEmpireRouter.sol";

contract Unileech is IUnileech {
    using SafeERC20 for IERC20;

    IEmpireRouter immutable router;

    constructor(address _router) public {
        router = IEmpireRouter(_router);
    }

    function leech(
        IEmpirePair pair,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external override {
        (address token0, address token1) = (pair.token0(), pair.token1());
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));

        require(amount0 > 0, "Unileech::leech: No Liquidity Leeched");

        if (token1 > token0) {
            uint256 tmp = amount0;
            amount0 = amount1;
            amount1 = tmp;
        }

        (uint256 amount0Consumed, uint256 amount1Consumed, ) =
            router.addLiquidity(
                token0,
                token1,
                amount0,
                amount1,
                amount0Min,
                amount1Min,
                msg.sender,
                deadline
            );

        if (amount0Consumed < amount0) {
            IERC20(token0).safeTransfer(msg.sender, amount0 - amount0Consumed);
        } else if (amount1Consumed < amount1) {
            IERC20(token1).safeTransfer(msg.sender, amount1 - amount1Consumed);
        }
    }
}
