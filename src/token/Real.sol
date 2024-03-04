// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {IMinter} from "../interfaces/IMinter.sol";

error Real__ZeroAddress();
error Real__NotMinter();

contract Real is ERC20 {
    address public minter;

    constructor(address _minter) ERC20("Real Ether", "reETH") {
        if (_minter == address(0)) revert Real__ZeroAddress();
        minter = _minter;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert Real__NotMinter();
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 value) external onlyMinter {
        _burn(from, value);
    }

    function tokenPrice() external view returns (uint256 price) {
        price = IMinter(minter).getTokenPrice();
    }
}
