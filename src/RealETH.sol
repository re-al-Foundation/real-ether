// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {Minter} from "./Minter.sol";

contract RealETH is ERC20 {
    address public minter;

    constructor(address _minter) ERC20("Real ETH", "rETH") {
        require(_minter != address(0), "ZERO ADDRESS");
        minter = _minter;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "!minter");
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 value) external onlyMinter {
        _burn(from, value);
    }

    function tokenPrice() public returns (uint256 price) {
        price = Minter(minter).getTokenPrice();
    }
}
