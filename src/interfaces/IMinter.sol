// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title Minter Interface
 * @dev Interface for a contract responsible for minting and burning tokens.
 */
interface IMinter {
    /**
     * @dev Sets a new vault address.
     * @param _vault The address of the new vault.
     */
    function setNewVault(address _vault) external;

    /**
     * @dev Mints tokens and assigns them to the specified address.
     * @param _to The address to which the minted tokens will be assigned.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @dev Burns tokens from the specified address.
     * @param _from The address from which tokens will be burned.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external;

    /**
     * @dev Gets the address of the real token.
     * @return The address of the real token.
     */
    function real() external view returns (address);

    /**
     * @dev Gets the address of the real token vault.
     * @return The address of the real token vault.
     */
    function vault() external view returns (address);

    /**
     * @dev Gets the price of the token.
     * @return price The price of the token.
     */
    function getTokenPrice() external view returns (uint256 price);
}
