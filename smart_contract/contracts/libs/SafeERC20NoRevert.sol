// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SafeERC20NoRevert
 * @dev Taken from OpenZeppelin's SafeERC20 implementation, just return a bool value without reverting
 * Clients using this function need to check for the return value themselves.
 */
library SafeERC20NoRevert {
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal returns (bool) {
        (bool success, bytes memory returndata) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
        return
            success &&
            (returndata.length == 0 || abi.decode(returndata, (bool))) &&
            address(token).code.length > 0;
    }
}