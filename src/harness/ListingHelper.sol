// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IPoolConfigurator,
    IAaveOracle,
    IAaveProtocolDataProvider,
    InitReserveInput,
    InterestRateData
} from "../interfaces/IAaveV3.sol";

/// @notice Risk/listing parameters the candidate chooses and justifies for a new market.
///         The plumbing (impls, init struct) is handled by {ListingHelper}; only these
///         values are the candidate's decision.
struct ListingParams {
    uint256 ltv; // bps, 1e4 = 100%
    uint256 liquidationThreshold; // bps
    uint256 liquidationBonus; // bps, >1e4 (e.g. 10800 = 8% bonus)
    uint256 reserveFactor; // bps
    uint256 supplyCap; // whole tokens (0 = unlimited)
    uint256 borrowCap; // whole tokens (0 = unlimited / disabled)
    bool borrowingEnabled;
    InterestRateData irParams; // interest-rate curve (bps fields)
}

/// @title ListingHelper
/// @notice Version-robust "list a new market" plumbing for Tydro (Aave v3.4 on Ink).
///         Discovers Tydro's own aToken / variableDebtToken implementations off an existing
///         reserve (rather than deploying fresh, version-mismatched ones) and runs the full
///         listing sequence in one call. The candidate supplies the asset, price source, and
///         the risk {ListingParams}; they do not re-plumb initReserves.
///
///         Uses Foundry cheatcodes (vm.load) to read the EIP-1967 implementation slot of the
///         reference reserve's token proxies, so it only runs under forge/anvil — which is all
///         the interview ever uses. It is never deployed to a live network.
library ListingHelper {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev EIP-1967 implementation slot.
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Derived Tydro contracts + a reference reserve to copy token impls from.
    struct Wiring {
        IPoolConfigurator configurator;
        IAaveOracle oracle;
        IAaveProtocolDataProvider dataProvider;
        address referenceReserve; // existing reserve (e.g. WETH) to clone impls from
    }

    /// @notice Read the aToken / variableDebtToken implementation addresses from the
    ///         reference reserve's proxies via their EIP-1967 slot.
    function discoverImpls(Wiring memory w)
        internal
        view
        returns (address aTokenImpl, address variableDebtTokenImpl)
    {
        (address aToken,, address variableDebtToken) =
            w.dataProvider.getReserveTokensAddresses(w.referenceReserve);
        aTokenImpl = address(uint160(uint256(vm.load(aToken, IMPL_SLOT))));
        variableDebtTokenImpl = address(uint160(uint256(vm.load(variableDebtToken, IMPL_SLOT))));
    }

    /// @notice Full listing sequence:
    ///         initReserves -> setAssetSources -> configureReserveAsCollateral ->
    ///         setReserveFactor -> setReserveBorrowing -> setSupplyCap/BorrowCap.
    /// @dev Must be called by an address holding the relevant ACL roles (the candidate EOA
    ///      after harness setup). interestRateData is the v3.4 compact IRM struct.
    function listMarket(Wiring memory w, address asset, address priceSource, ListingParams memory p) internal {
        string memory sym = IERC20Metadata(asset).symbol();

        // 1. Initialise the reserve (reusing Tydro's own token implementations).
        (address aTokenImpl, address variableDebtTokenImpl) = discoverImpls(w);
        InitReserveInput[] memory inputs = new InitReserveInput[](1);
        inputs[0] = InitReserveInput({
            aTokenImpl: aTokenImpl,
            variableDebtTokenImpl: variableDebtTokenImpl,
            underlyingAsset: asset,
            aTokenName: string.concat("Tydro ", sym),
            aTokenSymbol: string.concat("t", sym),
            variableDebtTokenName: string.concat("Tydro Variable Debt ", sym),
            variableDebtTokenSymbol: string.concat("variableDebt", sym),
            params: "",
            interestRateData: abi.encode(p.irParams)
        });
        w.configurator.initReserves(inputs);

        // 2. Point the oracle at the price source.
        address[] memory assets = new address[](1);
        address[] memory sources = new address[](1);
        assets[0] = asset;
        sources[0] = priceSource;
        w.oracle.setAssetSources(assets, sources);

        // 3. Collateral config (LTV / LT / bonus).
        w.configurator.configureReserveAsCollateral(
            asset, p.ltv, p.liquidationThreshold, p.liquidationBonus
        );

        // 4. Reserve factor.
        w.configurator.setReserveFactor(asset, p.reserveFactor);

        // 5. Borrowing.
        if (p.borrowingEnabled) {
            w.configurator.setReserveBorrowing(asset, true);
        }

        // 6. Caps.
        w.configurator.setSupplyCap(asset, p.supplyCap);
        w.configurator.setBorrowCap(asset, p.borrowCap);
    }
}
