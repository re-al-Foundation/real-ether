// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {RealETH} from "./RealETH.sol";
import {RealVault} from "../RealVault.sol";

contract Minter {
    address public realETH;
    address payable public vault;

    constructor(address _realETH, address payable _vault) {
        require(_realETH != address(0) && _vault != address(0), "ZERO ADDRESS");
        realETH = _realETH;
        vault = _vault;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "!vault");
        _;
    }

    function mint(address _to, uint256 _amount) external onlyVault {
        RealETH(realETH).mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyVault {
        RealETH(realETH).burn(_from, _amount);
    }

    function setNewVault(address _vault) external onlyVault {
        vault = payable(_vault);
    }

    function getTokenPrice() public view returns (uint256 price) {
        price = RealVault(vault).currentSharePrice();
    }
}
