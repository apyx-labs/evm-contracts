// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface ICurveTwocryptoNG {
    event AddLiquidity(
        address indexed provider,
        uint256[2] token_amounts,
        uint256 fee,
        uint256 token_supply,
        uint256 packed_price_scale
    );
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event ClaimAdminFee(address indexed admin, uint256[2] tokens);
    event NewParameters(
        uint256 mid_fee,
        uint256 out_fee,
        uint256 fee_gamma,
        uint256 allowed_extra_profit,
        uint256 adjustment_step,
        uint256 ma_time
    );
    event RampAgamma(
        uint256 initial_A,
        uint256 future_A,
        uint256 initial_gamma,
        uint256 future_gamma,
        uint256 initial_time,
        uint256 future_time
    );
    event RemoveLiquidity(address indexed provider, uint256[2] token_amounts, uint256 token_supply);
    event RemoveLiquidityOne(
        address indexed provider,
        uint256 token_amount,
        uint256 coin_index,
        uint256 coin_amount,
        uint256 approx_fee,
        uint256 packed_price_scale
    );
    event StopRampA(uint256 current_A, uint256 current_gamma, uint256 time);
    event TokenExchange(
        address indexed buyer,
        uint256 sold_id,
        uint256 tokens_sold,
        uint256 bought_id,
        uint256 tokens_bought,
        uint256 fee,
        uint256 packed_price_scale
    );
    event Transfer(address indexed sender, address indexed receiver, uint256 value);

    function A() external view returns (uint256);
    function ADMIN_FEE() external view returns (uint256);
    function D() external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function MATH() external view returns (address);
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external returns (uint256);
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount, address receiver)
        external
        returns (uint256);
    function adjustment_step() external view returns (uint256);
    function admin() external view returns (address);
    function allowance(address arg0, address arg1) external view returns (uint256);
    function allowed_extra_profit() external view returns (uint256);
    function apply_new_parameters(
        uint256 _new_mid_fee,
        uint256 _new_out_fee,
        uint256 _new_fee_gamma,
        uint256 _new_allowed_extra_profit,
        uint256 _new_adjustment_step,
        uint256 _new_ma_time
    ) external;
    function approve(address _spender, uint256 _value) external returns (bool);
    function balanceOf(address arg0) external view returns (uint256);
    function balances(uint256 arg0) external view returns (uint256);
    function calc_token_amount(uint256[2] memory amounts, bool deposit) external view returns (uint256);
    function calc_token_fee(uint256[2] memory amounts, uint256[2] memory xp) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 token_amount, uint256 i) external view returns (uint256);
    function coins(uint256 arg0) external view returns (address);
    function decimals() external view returns (uint8);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy, address receiver) external returns (uint256);
    function exchange_received(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function exchange_received(uint256 i, uint256 j, uint256 dx, uint256 min_dy, address receiver)
        external
        returns (uint256);
    function factory() external view returns (address);
    function fee() external view returns (uint256);
    function fee_calc(uint256[2] memory xp) external view returns (uint256);
    function fee_gamma() external view returns (uint256);
    function fee_receiver() external view returns (address);
    function future_A_gamma() external view returns (uint256);
    function future_A_gamma_time() external view returns (uint256);
    function gamma() external view returns (uint256);
    function get_dx(uint256 i, uint256 j, uint256 dy) external view returns (uint256);
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function initial_A_gamma() external view returns (uint256);
    function initial_A_gamma_time() external view returns (uint256);
    function last_prices() external view returns (uint256);
    function last_timestamp() external view returns (uint256);
    function lp_price() external view returns (uint256);
    function ma_time() external view returns (uint256);
    function mid_fee() external view returns (uint256);
    function name() external view returns (string memory);
    function nonces(address arg0) external view returns (uint256);
    function out_fee() external view returns (uint256);
    function packed_fee_params() external view returns (uint256);
    function packed_rebalancing_params() external view returns (uint256);
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool);
    function precisions() external view returns (uint256[2] memory);
    function price_oracle() external view returns (uint256);
    function price_scale() external view returns (uint256);
    function ramp_A_gamma(uint256 future_A, uint256 future_gamma, uint256 future_time) external;
    function remove_liquidity(uint256 _amount, uint256[2] memory min_amounts) external returns (uint256[2] memory);
    function remove_liquidity(uint256 _amount, uint256[2] memory min_amounts, address receiver)
        external
        returns (uint256[2] memory);
    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount) external returns (uint256);
    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount, address receiver)
        external
        returns (uint256);
    function salt() external view returns (bytes32);
    function stop_ramp_A_gamma() external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    function version() external view returns (string memory);
    function virtual_price() external view returns (uint256);
    function xcp_profit() external view returns (uint256);
    function xcp_profit_a() external view returns (uint256);
}
