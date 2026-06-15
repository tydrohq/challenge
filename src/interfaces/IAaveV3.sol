// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal Aave v3 interfaces used by the Tydro harness.
/// @notice Signatures are pinned to Tydro's deployed version (Aave v3.4, solc 0.8.27) as
///         discovered off the Ink fork. In particular, `InitReserveInput` below is the
///         exact 9-field v3.4 shape taken from the verified PoolConfigurator ABI on the
///         Ink explorer — NOT the older v3.0/v3.1 shape.

interface IPoolAddressesProvider {
    function getPool() external view returns (address);
    function getPoolConfigurator() external view returns (address);
    function getPriceOracle() external view returns (address);
    function getACLManager() external view returns (address);
    function getACLAdmin() external view returns (address);
}

interface IAaveOracle {
    function setAssetSources(address[] calldata assets, address[] calldata sources) external;
    function getAssetPrice(address asset) external view returns (uint256);
    function getSourceOfAsset(address asset) external view returns (address);
    function BASE_CURRENCY_UNIT() external view returns (uint256);
}

/// @notice Chainlink-style price source. Prices are USD at 8 decimals (Aave base currency).
interface IAggregatorInterface {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

/// @notice Aave v3.4 reserve-initialisation input (the version-sensitive struct).
///         Fields verified against Tydro's PoolConfigurator ABI on Ink.
struct InitReserveInput {
    address aTokenImpl;
    address variableDebtTokenImpl;
    address underlyingAsset;
    string aTokenName;
    string aTokenSymbol;
    string variableDebtTokenName;
    string variableDebtTokenSymbol;
    bytes params;
    bytes interestRateData;
}

/// @notice v3.4 shared interest-rate strategy params (compact, basis points where 1e4 = 100%).
///         Encoded into InitReserveInput.interestRateData via abi.encode.
struct InterestRateData {
    uint16 optimalUsageRatio;
    uint32 baseVariableBorrowRate;
    uint32 variableRateSlope1;
    uint32 variableRateSlope2;
}

interface IPoolConfigurator {
    function initReserves(InitReserveInput[] calldata input) external;
    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;
    function setReserveFactor(address asset, uint256 newReserveFactor) external;
    function setSupplyCap(address asset, uint256 newSupplyCap) external;
    function setBorrowCap(address asset, uint256 newBorrowCap) external;
    function setReserveBorrowing(address asset, bool enabled) external;
}

interface IAaveProtocolDataProvider {
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress);
    function getInterestRateStrategyAddress(address asset) external view returns (address);
}

interface IACLManager {
    function addPoolAdmin(address admin) external;
    function addRiskAdmin(address admin) external;
    function addAssetListingAdmin(address admin) external;
    function addEmergencyAdmin(address admin) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}

interface IPool {
    function getReservesList() external view returns (address[] memory);
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
}

interface IAToken {
    function balanceOf(address user) external view returns (uint256);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
