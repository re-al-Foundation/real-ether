// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {IReal} from "../interfaces/IReal.sol";
import {IRealVault} from "../interfaces/IRealVault.sol";

error Minter__ZeroAddress();
error Minter__NotVault();

contract Minter {
    address public real;
    address payable public vault;

    event VaultUpdated(address oldRealVault, address newRealVault);

    constructor(address _real, address payable _vault) {
        if (_real == address(0) || _vault == address(0)) revert Minter__ZeroAddress();
        real = _real;
        vault = _vault;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Minter__NotVault();
        _;
    }

    function mint(address _to, uint256 _amount) external onlyVault {
        IReal(real).mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyVault {
        IReal(real).burn(_from, _amount);
    }

    function setNewVault(address _vault) external onlyVault {
        address _oldRealVault = vault;
        vault = payable(_vault);
        emit VaultUpdated(_oldRealVault, _vault);
    }

    function getTokenPrice() public view returns (uint256 price) {
        price = IRealVault(vault).currentSharePrice();
    }
}
