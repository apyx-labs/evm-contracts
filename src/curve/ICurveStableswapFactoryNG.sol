// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

// Generated using:
// cast interface 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf > src/curve/ICurveStableswapFactoryNG.sol

interface CurveStableswapFactoryNG {
    event BasePoolAdded(address base_pool);
    event LiquidityGaugeDeployed(address pool, address gauge);
    event MetaPoolDeployed(address coin, address base_pool, uint256 A, uint256 fee, address deployer);
    event PlainPoolDeployed(address[] coins, uint256 A, uint256 fee, address deployer);

    function asset_types(uint8 arg0) external view returns (string memory);

    // ========================================
    // Pool deployment methods
    // ========================================

    function deploy_gauge(address _pool) external returns (address);

    function deploy_plain_pool(
        string memory _name,
        string memory _symbol,
        address[] memory _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _offpeg_fee_multiplier,
        uint256 _ma_exp_time,
        uint256 _implementation_idx,
        uint8[] memory _asset_types,
        bytes4[] memory _method_ids,
        address[] memory _oracles
    ) external returns (address);

    function deploy_metapool(
        address _base_pool,
        string memory _name,
        string memory _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee,
        uint256 _offpeg_fee_multiplier,
        uint256 _ma_exp_time,
        uint256 _implementation_idx,
        uint8 _asset_type,
        bytes4 _method_id,
        address _oracle
    ) external returns (address);

    function find_pool_for_coins(address _from, address _to) external view returns (address);

    function find_pool_for_coins(address _from, address _to, uint256 i) external view returns (address);

    // ========================================
    // Pool iteration methods
    // ========================================

    function pool_count() external view returns (uint256);
    function pool_list(uint256 arg0) external view returns (address);

    // ========================================
    // Pool data methods
    // ========================================

    function get_A(address _pool) external view returns (uint256);
    function get_balances(address _pool) external view returns (uint256[] memory);
    function get_base_pool(address _pool) external view returns (address);
    function get_coin_indices(address _pool, address _from, address _to) external view returns (int128, int128, bool);
    function get_coins(address _pool) external view returns (address[] memory);
    function get_decimals(address _pool) external view returns (uint256[] memory);
    function get_fees(address _pool) external view returns (uint256, uint256);
    function get_gauge(address _pool) external view returns (address);
    function get_implementation_address(address _pool) external view returns (address);
    function get_meta_n_coins(address _pool) external view returns (uint256, uint256);
    function get_metapool_rates(address _pool) external view returns (uint256[] memory);
    function get_n_coins(address _pool) external view returns (uint256);
    function get_pool_asset_types(address _pool) external view returns (uint8[] memory);
    function get_underlying_balances(address _pool) external view returns (uint256[] memory);
    function get_underlying_coins(address _pool) external view returns (address[] memory);
    function get_underlying_decimals(address _pool) external view returns (uint256[] memory);
    function is_meta(address _pool) external view returns (bool);

    // ========================================
    // Implementation getters
    // ========================================

    function gauge_implementation() external view returns (address);
    function math_implementation() external view returns (address);
    function metapool_implementations(uint256 arg0) external view returns (address);
    function pool_implementations(uint256 arg0) external view returns (address);
    function views_implementation() external view returns (address);
}
