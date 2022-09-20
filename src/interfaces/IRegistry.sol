/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
pragma solidity >=0.4.22 <0.9.0;

interface IRegistry {
    function batchIsWhiteListed(address[] calldata assetAddresses, uint256[] calldata assetIds)
        external
        view
        returns (bool);

    function getTotalValue(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        uint256 baseCurrency
    )
        external
        view
        returns (uint256);

    function getCollateralValue(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        address baseCurrency
    )
        external
        view
        returns (uint256);

    function getCollateralFactor(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        address baseCurrency
    )
        external
        view
        returns (uint256);

    function getLiquidationValue(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        uint256 baseCurrency,
        uint256 openDebt
    )
        external
        view
        returns (uint256);

    function getLiquidationThreshold(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        address baseCurrency
    )
        external
        view
        returns (uint16);

    function getTotalValue(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        address baseCurrency
    )
        external
        view
        returns (uint256);

    function getListOfValuesPerCreditRating(
        address[] calldata _assetAddresses,
        uint256[] calldata _assetIds,
        uint256[] calldata _assetAmounts,
        uint256 baseCurrency
    )
        external
        view
        returns (uint256[] memory);

    function assetToBaseCurrency(address baseCurrency) external view returns (uint8 baseCurrencyIdentifier);
}
