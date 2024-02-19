/// This module keeps track of a users deposits and borrows within a specific lending market.
module suilend::obligation {
    // === Imports ===
    use std::type_name::{TypeName, Self};
    use sui::object::{Self, UID};
    use std::vector::{Self};
    use sui::tx_context::{TxContext};
    use suilend::reserve::{Self, Reserve, config};
    use suilend::reserve_config::{open_ltv, close_ltv, borrow_weight, liquidation_bonus};
    use sui::clock::{Clock};
    use suilend::decimal::{Self, Decimal, mul, add, sub, div, gt, lt, min, ceil, floor, le};

    #[test_only]
    use sui::test_scenario::{Self, Scenario};

    #[test_only]
    use sui::clock::{Self};

    // === Friends ===
    friend suilend::lending_market;

    // === Errors ===
    const EObligationIsNotLiquidatable: u64 = 0;
    const EObligationIsNotHealthy: u64 = 1;
    const EBorrowNotFound: u64 = 2;
    const EDepositNotFound: u64 = 3;

    // === Constants ===
    const CLOSE_FACTOR_PCT: u8 = 20;

    // === Structs ===
    struct Obligation<phantom P> has key, store {
        id: UID,

        deposits: vector<Deposit>,
        borrows: vector<Borrow>,

        /// value of all deposits in USD
        deposited_value_usd: Decimal,
        /// sum(deposit value * open ltv) for all deposits.
        /// if weighted_borrowed_value_usd > allowed_borrow_value_usd, 
        /// the obligation is not healthy
        allowed_borrow_value_usd: Decimal,
        /// sum(deposit value * close ltv) for all deposits
        /// if weighted_borrowed_value_usd > unhealthy_borrow_value_usd, 
        /// the obligation is unhealthy and can be liquidated
        unhealthy_borrow_value_usd: Decimal,

        /// value of all borrows in USD
        unweighted_borrowed_value_usd: Decimal,
        /// weighted value of all borrows in USD
        weighted_borrowed_value_usd: Decimal,
        /// weighted value of all borrows in USD, but using the upper bound of the market value
        weighted_borrowed_value_upper_bound_usd: Decimal,
    }

    struct Deposit has store {
        coin_type: TypeName,
        reserve_array_index: u64,
        deposited_ctoken_amount: u64,
        market_value: Decimal,
    }

    struct Borrow has store {
        coin_type: TypeName,
        reserve_array_index: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        market_value: Decimal
    }

    // === Public-Friend Functions
    public(friend) fun create_obligation<P>(ctx: &mut TxContext): Obligation<P> {
        Obligation<P> {
            id: object::new(ctx),
            deposits: vector::empty(),
            borrows: vector::empty(),
            deposited_value_usd: decimal::from(0),
            unweighted_borrowed_value_usd: decimal::from(0),
            weighted_borrowed_value_usd: decimal::from(0),
            weighted_borrowed_value_upper_bound_usd: decimal::from(0),
            allowed_borrow_value_usd: decimal::from(0),
            unhealthy_borrow_value_usd: decimal::from(0)
        }
    }


    /// update the obligation's borrowed amounts and health values. this is 
    /// called by the lending market prior to any borrow, withdraw, or liquidate operation.
    public(friend) fun refresh<P>(
        obligation: &mut Obligation<P>,
        reserves: &mut vector<Reserve<P>>,
        clock: &Clock
    ) {
        let i = 0;
        let deposited_value_usd = decimal::from(0);
        let allowed_borrow_value_usd = decimal::from(0);
        let unhealthy_borrow_value_usd = decimal::from(0);

        while (i < vector::length(&obligation.deposits)) {
            let deposit = vector::borrow_mut(&mut obligation.deposits, i);

            let deposit_reserve = vector::borrow_mut(reserves, deposit.reserve_array_index);

            reserve::compound_interest(deposit_reserve, clock);
            reserve::assert_price_is_fresh(deposit_reserve, clock);

            let market_value = reserve::ctoken_market_value(
                deposit_reserve,
                deposit.deposited_ctoken_amount
            );
            let market_value_lower_bound = reserve::ctoken_market_value_lower_bound(
                deposit_reserve,
                deposit.deposited_ctoken_amount
            );

            deposit.market_value = market_value;
            deposited_value_usd = add(deposited_value_usd, market_value);
            allowed_borrow_value_usd = add(
                allowed_borrow_value_usd,
                mul(
                    market_value_lower_bound,
                    open_ltv(config(deposit_reserve))
                )
            );
            unhealthy_borrow_value_usd = add(
                unhealthy_borrow_value_usd,
                mul(
                    market_value,
                    close_ltv(config(deposit_reserve))
                )
            );

            i = i + 1;
        };

        obligation.deposited_value_usd = deposited_value_usd;
        obligation.allowed_borrow_value_usd = allowed_borrow_value_usd;
        obligation.unhealthy_borrow_value_usd = unhealthy_borrow_value_usd;

        let i = 0;
        let unweighted_borrowed_value_usd = decimal::from(0);
        let weighted_borrowed_value_usd = decimal::from(0);
        let weighted_borrowed_value_upper_bound_usd = decimal::from(0);

        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow_mut(&mut obligation.borrows, i);

            let borrow_reserve = vector::borrow_mut(reserves, borrow.reserve_array_index);
            reserve::compound_interest(borrow_reserve, clock);
            reserve::assert_price_is_fresh(borrow_reserve, clock);

            compound_debt(borrow, borrow_reserve);

            let market_value = reserve::market_value(borrow_reserve, borrow.borrowed_amount);
            let market_value_upper_bound = reserve::market_value_upper_bound(
                borrow_reserve, 
                borrow.borrowed_amount
            ); 

            borrow.market_value = market_value;
            unweighted_borrowed_value_usd = add(unweighted_borrowed_value_usd, market_value);
            weighted_borrowed_value_usd = add(
                weighted_borrowed_value_usd,
                mul(
                    market_value,
                    borrow_weight(config(borrow_reserve))
                )
            );
            weighted_borrowed_value_upper_bound_usd = add(
                weighted_borrowed_value_upper_bound_usd,
                mul(
                    market_value_upper_bound,
                    borrow_weight(config(borrow_reserve))
                )
            );

            i = i + 1;
        };

        obligation.unweighted_borrowed_value_usd = unweighted_borrowed_value_usd;
        obligation.weighted_borrowed_value_usd = weighted_borrowed_value_usd;
        obligation.weighted_borrowed_value_upper_bound_usd = weighted_borrowed_value_upper_bound_usd;
    }

    /// Process a deposit action
    public(friend) fun deposit<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        let deposit = find_or_add_deposit(obligation, reserve);
        deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount + ctoken_amount;

        let deposit_value = reserve::ctoken_market_value(reserve, ctoken_amount);

        // update other health values. note that we don't enforce price freshness here. this is purely
        // to make offchain accounting easier. any operation that requires price 
        // freshness (withdraw, borrow, liquidate) will refresh the obligation right before.
        deposit.market_value = add(deposit.market_value, deposit_value);
        obligation.deposited_value_usd = add(obligation.deposited_value_usd, deposit_value);
        obligation.allowed_borrow_value_usd = add(
            obligation.allowed_borrow_value_usd,
            mul(
                reserve::ctoken_market_value_lower_bound(reserve, ctoken_amount),
                open_ltv(config(reserve))
            )
        );
        obligation.unhealthy_borrow_value_usd = add(
            obligation.unhealthy_borrow_value_usd,
            mul(
                deposit_value,
                close_ltv(config(reserve))
            )
        );
    }

    /// Process a borrow action. Makes sure that the obligation is healthy after the borrow.
    public(friend) fun borrow<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        amount: u64,
    ) {
        let borrow = find_or_add_borrow(obligation, reserve);

        borrow.borrowed_amount = add(borrow.borrowed_amount, decimal::from(amount));

        // update health values
        let borrow_market_value = reserve::market_value(reserve, decimal::from(amount));
        let borrow_market_value_upper_bound = reserve::market_value_upper_bound(reserve, decimal::from(amount));

        borrow.market_value = add(borrow.market_value, borrow_market_value);
        obligation.unweighted_borrowed_value_usd = add(
            obligation.unweighted_borrowed_value_usd, 
            borrow_market_value
        );
        obligation.weighted_borrowed_value_usd = add(
            obligation.weighted_borrowed_value_usd, 
            mul(borrow_market_value, borrow_weight(config(reserve)))
        );
        obligation.weighted_borrowed_value_upper_bound_usd = add(
            obligation.weighted_borrowed_value_upper_bound_usd, 
            mul(borrow_market_value_upper_bound, borrow_weight(config(reserve)))
        );

        assert!(is_healthy(obligation), EObligationIsNotHealthy);
    }

    /// Process a repay action
    public(friend) fun repay<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        repay_amount: Decimal,
    ) {
        let borrow = find_borrow_mut(obligation, reserve);

        let old_borrow_amount = borrow.borrowed_amount;
        compound_debt(borrow, reserve);
        let interest_diff = sub(borrow.borrowed_amount, old_borrow_amount);

        borrow.borrowed_amount = sub(borrow.borrowed_amount, repay_amount);

        // update other health values. note that we don't enforce price freshness here. this is purely
        // to make offchain accounting easier. any operation that requires price 
        // freshness (withdraw, borrow, liquidate) will refresh the obligation right before.
        if (le(interest_diff, repay_amount)) {
            let diff = sub(repay_amount, interest_diff);
            let repay_value = reserve::market_value(reserve, diff);
            let repay_value_upper_bound = reserve::market_value_upper_bound(reserve, diff);

            borrow.market_value = sub(borrow.market_value, repay_value);
            obligation.unweighted_borrowed_value_usd = sub(
                obligation.unweighted_borrowed_value_usd,
                repay_value
            );
            obligation.weighted_borrowed_value_usd = sub(
                obligation.weighted_borrowed_value_usd,
                mul(repay_value, borrow_weight(config(reserve)))
            );
            obligation.weighted_borrowed_value_upper_bound_usd = sub(
                obligation.weighted_borrowed_value_upper_bound_usd,
                mul(repay_value_upper_bound, borrow_weight(config(reserve)))
            );
        }
        else {
            let additional_borrow_amount = sub(interest_diff, repay_amount);
            let additional_borrow_value = reserve::market_value(reserve, additional_borrow_amount);
            let additional_borrow_value_upper_bound = reserve::market_value_upper_bound(reserve, additional_borrow_amount);

            borrow.market_value = add(borrow.market_value, additional_borrow_value);
            obligation.unweighted_borrowed_value_usd = add(
                obligation.unweighted_borrowed_value_usd,
                additional_borrow_value 
            );
            obligation.weighted_borrowed_value_usd = add(
                obligation.weighted_borrowed_value_usd,
                mul(additional_borrow_value, borrow_weight(config(reserve)))
            );
            obligation.weighted_borrowed_value_upper_bound_usd = add(
                obligation.weighted_borrowed_value_upper_bound_usd,
                mul(additional_borrow_value_upper_bound, borrow_weight(config(reserve)))
            );
        }

    }

    /// Process a withdraw action. Makes sure that the obligation is healthy after the withdraw.
    public(friend) fun withdraw<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        withdraw_unchecked(obligation, reserve, ctoken_amount);

        assert!(is_healthy(obligation), EObligationIsNotHealthy);
    }

    /// Process a liquidate action.
    /// Returns the amount of ctokens to withdraw, and the amount of tokens to repay.
    public(friend) fun liquidate<P>(
        obligation: &mut Obligation<P>,
        repay_reserve: &Reserve<P>,
        withdraw_reserve: &Reserve<P>,
        repay_amount: u64,
    ): (u64, u64) {
        assert!(is_liquidatable(obligation), EObligationIsNotLiquidatable);

        let borrow = find_borrow(obligation, repay_reserve);
        let deposit = find_deposit(obligation, withdraw_reserve);

        let repay_amount = {
            // we can liquidate up to 20% of the obligation's market value
            let max_repay_value = min(
                mul(
                    obligation.weighted_borrowed_value_usd,
                    decimal::from_percent(CLOSE_FACTOR_PCT)
                ),
                borrow.market_value
            );

            // <= 1
            let max_repay_pct = div(max_repay_value, borrow.market_value);
            min(
                mul(max_repay_pct, borrow.borrowed_amount),
                decimal::from(repay_amount)
            )
        };

        let repay_value = reserve::market_value(repay_reserve, repay_amount);
        let withdraw_value = mul(
            repay_value, 
            add(decimal::from(1), liquidation_bonus(config(withdraw_reserve)))
        );

        let final_repay_amount;
        let final_settle_amount;
        let final_withdraw_amount;

        if (lt(deposit.market_value, withdraw_value)) {
            let repay_pct = div(deposit.market_value, withdraw_value);

            final_settle_amount = mul(repay_amount, repay_pct);
            final_repay_amount = ceil(final_settle_amount);
            final_withdraw_amount = deposit.deposited_ctoken_amount;
        }
        else {
            let withdraw_pct = div(withdraw_value, deposit.market_value);

            final_settle_amount = repay_amount;
            final_repay_amount = ceil(final_settle_amount);
            final_withdraw_amount = floor(
                mul(decimal::from(deposit.deposited_ctoken_amount), withdraw_pct)
            );
        };

        repay(obligation, repay_reserve, final_settle_amount);
        withdraw_unchecked(obligation, withdraw_reserve, final_withdraw_amount);

        (final_withdraw_amount, final_repay_amount)
    }

    // === Public-View Functions
    public fun deposited_ctoken_amount<P, T>(obligation: &Obligation<P>): u64 {
        let i = 0;
        while (i < vector::length(&obligation.deposits)) {
            let deposit = vector::borrow(&obligation.deposits, i);
            if (deposit.coin_type == type_name::get<T>()) {
                return deposit.deposited_ctoken_amount
            };

            i = i + 1;
        };

        0
    }

    public fun borrowed_amount<P, T>(obligation: &Obligation<P>): Decimal {
        let i = 0;
        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow(&obligation.borrows, i);
            if (borrow.coin_type == type_name::get<T>()) {
                return borrow.borrowed_amount
            };

            i = i + 1;
        };

        decimal::from(0)
    }


    public fun is_healthy<P>(obligation: &Obligation<P>): bool {
        le(obligation.weighted_borrowed_value_upper_bound_usd, obligation.allowed_borrow_value_usd)
    }

    public fun is_liquidatable<P>(obligation: &Obligation<P>): bool {
        gt(obligation.weighted_borrowed_value_usd, obligation.unhealthy_borrow_value_usd)
    }

    // === Private Functions ===
    /// Withdraw without checking if the obligation is healthy.
    fun withdraw_unchecked<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        let deposit = find_deposit_mut(obligation, reserve);

        let withdraw_market_value = reserve::ctoken_market_value(reserve, ctoken_amount);

        // update health values
        deposit.market_value = sub(deposit.market_value, withdraw_market_value);
        deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount - ctoken_amount;

        obligation.deposited_value_usd = sub(obligation.deposited_value_usd, withdraw_market_value);
        obligation.allowed_borrow_value_usd = sub(
            obligation.allowed_borrow_value_usd,
            mul(
                // need to use lower bound to keep calculation consistent
                reserve::ctoken_market_value_lower_bound(reserve, ctoken_amount),
                open_ltv(config(reserve))
            )
        );
        obligation.unhealthy_borrow_value_usd = sub(
            obligation.unhealthy_borrow_value_usd,
            mul(
                withdraw_market_value,
                close_ltv(config(reserve))
            )
        );
    }

    /// Compound the debt on a borrow object
    fun compound_debt<P>(borrow: &mut Borrow, reserve: &Reserve<P>) {
        let new_cumulative_borrow_rate = reserve::cumulative_borrow_rate(reserve);

        let compounded_interest_rate = div(
            new_cumulative_borrow_rate,
            borrow.cumulative_borrow_rate
        );

        borrow.borrowed_amount = mul(
            borrow.borrowed_amount,
            compounded_interest_rate
        );

        borrow.cumulative_borrow_rate = new_cumulative_borrow_rate;
    }

    fun find_deposit_index<P>(
        obligation: &Obligation<P>,
        reserve: &Reserve<P>,
    ): u64 {
        let i = 0;
        while (i < vector::length(&obligation.deposits)) {
            let deposit = vector::borrow(&obligation.deposits, i);
            if (deposit.reserve_array_index == reserve::array_index(reserve)) {
                return i
            };

            i = i + 1;
        };

        i
    }

    fun find_borrow_index<P>(
        obligation: &Obligation<P>,
        reserve: &Reserve<P>,
    ): u64 {
        let i = 0;
        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow(&obligation.borrows, i);
            if (borrow.reserve_array_index == reserve::array_index(reserve)) {
                return i
            };

            i = i + 1;
        };

        i
    }

    fun find_borrow_mut<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
    ): &mut Borrow {
        let i = find_borrow_index(obligation, reserve);
        assert!(i < vector::length(&obligation.borrows), EBorrowNotFound);

        vector::borrow_mut(&mut obligation.borrows, i)
    }

    fun find_borrow<P>(
        obligation: &Obligation<P>,
        reserve: &Reserve<P>,
    ): &Borrow {
        let i = find_borrow_index(obligation, reserve);
        assert!(i < vector::length(&obligation.borrows), EBorrowNotFound);

        vector::borrow(&obligation.borrows, i)
    }

    fun find_deposit_mut<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
    ): &mut Deposit {
        let i = find_deposit_index(obligation, reserve);
        assert!(i < vector::length(&obligation.deposits), EDepositNotFound);

        vector::borrow_mut(&mut obligation.deposits, i)
    }

    fun find_deposit<P>(
        obligation: &Obligation<P>,
        reserve: &Reserve<P>,
    ): &Deposit {
        let i = find_deposit_index(obligation, reserve);
        assert!(i < vector::length(&obligation.deposits), EDepositNotFound);

        vector::borrow(&obligation.deposits, i)
    }   

    fun find_or_add_borrow<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
    ): &mut Borrow {
        let i = find_borrow_index(obligation, reserve);
        if (i < vector::length(&obligation.borrows)) {
            return vector::borrow_mut(&mut obligation.borrows, i)
        };

        let borrow = Borrow {
            coin_type: reserve::coin_type(reserve),
            reserve_array_index: reserve::array_index(reserve),
            borrowed_amount: decimal::from(0),
            cumulative_borrow_rate: reserve::cumulative_borrow_rate(reserve),
            market_value: decimal::from(0)
        };

        vector::push_back(&mut obligation.borrows, borrow);
        let length = vector::length(&obligation.borrows);
        vector::borrow_mut(&mut obligation.borrows, length - 1)
    }

    fun find_or_add_deposit<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>
    ): &mut Deposit {
        let i = find_deposit_index(obligation, reserve);
        if (i < vector::length(&obligation.deposits)) {
            return vector::borrow_mut(&mut obligation.deposits, i)
        };

        let deposit = Deposit {
            coin_type: reserve::coin_type(reserve),
            reserve_array_index: reserve::array_index(reserve),
            deposited_ctoken_amount: 0,
            market_value: decimal::from(0)
        };

        vector::push_back(&mut obligation.deposits, deposit);
        let length = vector::length(&obligation.deposits);
        vector::borrow_mut(&mut obligation.deposits, length - 1)
    }

    // === Test Functions ===
    #[test_only]
    struct TEST_MARKET {}

    #[test_only]
    struct TEST_SUI {}

    #[test_only]
    struct TEST_USDC {}

    #[test_only]
    struct TEST_USDT {}

    #[test_only]
    struct TEST_ETH {}

    #[test_only]
    use suilend::reserve_config::{Self};

    #[test_only]
    fun sui_reserve<P>(scenario: &mut Scenario): Reserve<P> {
        let config = reserve_config::create_reserve_config(
            // open ltv
            20,
            // close ltv
            50,
            // borrow weight bps
            20_000,
            // deposit limit
            1_000_000,
            // borrow limit
            1_000_000,
            // liquidation bonus pct
            10,
            // borrow fee bps
            0,
            // spread_fee_bps
            0,
            // liquidation_fee_bps
            0,
            // interest rate utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 31536000 * 4);
                vector::push_back(&mut v, 31536000 * 8);
                v
            },
            test_scenario::ctx(scenario)
        );

        reserve::create_for_testing<P, TEST_SUI>(
            config,
            0,
            9,
            decimal::from(10),
            0,
            0,
            0,
            decimal::from(0),
            decimal::from(3),
            0,
            test_scenario::ctx(scenario)
        )
    }

    #[test_only]
    fun usdc_reserve<P>(scenario: &mut Scenario): Reserve<P> {
        let config = reserve_config::create_reserve_config(
            // open ltv
            50,
            // close ltv
            80,
            // borrow weight bps
            20_000,
            // deposit limit
            1_000_000,
            // borrow limit
            1_000_000,
            // liquidation bonus pct
            5,
            // borrow fee bps
            0,
            // spread_fee_bps
            0,
            // liquidation_fee_bps
            0,
            // interest rate utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 3153600000);
                vector::push_back(&mut v, 3153600000 * 2);
                v
            },
            test_scenario::ctx(scenario)
        );

        reserve::create_for_testing<P, TEST_USDC>(
            config,
            1,
            6,
            decimal::from(1),
            0,
            0,
            0,
            decimal::from(0),
            decimal::from(2),
            0,
            test_scenario::ctx(scenario)
        )
    }

    #[test_only]
    fun usdt_reserve<P>(scenario: &mut Scenario): Reserve<P> {
        let config = reserve_config::create_reserve_config(
            // open ltv
            50,
            // close ltv
            80,
            // borrow weight bps
            20_000,
            // deposit limit
            1_000_000,
            // borrow limit
            1_000_000,
            // liquidation bonus pct
            5,
            // borrow fee bps
            0,
            // spread_fee_bps
            0,
            // liquidation_fee_bps
            0,
            // interest rate utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 3153600000);
                vector::push_back(&mut v, 3153600000 * 2);
                v
            },
            test_scenario::ctx(scenario)
        );

        reserve::create_for_testing<P, TEST_USDT>(
            config,
            2,
            6,
            decimal::from(1),
            0,
            0,
            0,
            decimal::from(0),
            decimal::from(2),
            0,
            test_scenario::ctx(scenario)
        )
    }

    #[test_only]
    fun eth_reserve<P>(scenario: &mut Scenario): Reserve<P> {
        let config = reserve_config::create_reserve_config(
            // open ltv
            10,
            // close ltv
            20,
            // borrow weight bps
            30_000,
            // deposit limit
            1_000_000,
            // borrow limit
            1_000_000,
            // liquidation bonus pct
            5,
            // borrow fee bps
            0,
            // spread_fee_bps
            0,
            // liquidation_fee_bps
            0,
            // interest rate utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 3153600000 * 10);
                vector::push_back(&mut v, 3153600000 * 20);
                v
            },
            test_scenario::ctx(scenario)
        );

        reserve::create_for_testing<P, TEST_ETH>(
            config,
            3,
            8,
            decimal::from(2000),
            0,
            0,
            0,
            decimal::from(0),
            decimal::from(3),
            0,
            test_scenario::ctx(scenario)
        )
    }

    #[test_only]
    fun reserves<P>(scenario: &mut Scenario): vector<Reserve<P>> {
        let v = vector::empty();
        vector::push_back(&mut v, sui_reserve(scenario));
        vector::push_back(&mut v,  usdc_reserve(scenario));
        vector::push_back(&mut v,  usdt_reserve(scenario));
        vector::push_back(&mut v,  eth_reserve(scenario));

        v
    }

    #[test_only]
    fun get_reserve_array_index<P, T>(reserves: &vector<Reserve<P>>): u64 {
        let i = 0;
        while (i < vector::length(reserves)) {
            let reserve = vector::borrow(reserves, i);
            if (type_name::get<T>() == reserve::coin_type(reserve)) {
                return i
            };

            i = i + 1;
        };

        i
    }

    #[test_only]
    fun get_reserve<P, T>(reserves: &vector<Reserve<P>>): &Reserve<P> {
        let i = get_reserve_array_index<P, T>(reserves);
        assert!(i < vector::length(reserves), 0);
        vector::borrow(reserves, i)
    }

    #[test_only]
    fun get_reserve_mut<P, T>(reserves: &mut vector<Reserve<P>>): &mut Reserve<P> {
        let i = get_reserve_array_index<P, T>(reserves);
        assert!(i < vector::length(reserves), 0);
        vector::borrow_mut(reserves, i)
    }


    #[test]
    public fun test_deposit() {
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        reserve::update_price_for_testing(
            &mut usdc_reserve, 
            &clock, 
            decimal::from(1), 
            decimal::from_percent(90)
        );
        reserve::update_price_for_testing(
            &mut sui_reserve, 
            &clock, 
            decimal::from(10), 
            decimal::from(9)
        );

        deposit<TEST_MARKET>(&mut obligation, &usdc_reserve, 100 * 1_000_000);
        deposit<TEST_MARKET>(&mut obligation, &usdc_reserve, 100 * 1_000_000);
        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);

        assert!(vector::length(&obligation.deposits) == 2, 0);

        let usdc_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(usdc_deposit.deposited_ctoken_amount == 200 * 1_000_000, 1);
        assert!(usdc_deposit.market_value == decimal::from(200), 2);

        let sui_deposit = vector::borrow(&obligation.deposits, 1);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        assert!(vector::length(&obligation.borrows) == 0, 0);
        assert!(obligation.deposited_value_usd == decimal::from(1200), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(270), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(660), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(0), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(0), 4);

        test_utils::destroy(usdc_reserve);
        test_utils::destroy(sui_reserve);
        test_utils::destroy(obligation);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EObligationIsNotHealthy)]
    public fun test_borrow_fail() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 200 * 1_000_000 + 1);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_borrow_happy() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        reserve::update_price_for_testing(
            &mut usdc_reserve, 
            &clock, 
            decimal::from(1), 
            decimal::from(2)
        );
        reserve::update_price_for_testing(
            &mut sui_reserve, 
            &clock, 
            decimal::from(10), 
            decimal::from(5)
        );

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 12_500_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 12_500_000);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(25 * 1_000_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from(2), 2);
        assert!(usdc_borrow.market_value == decimal::from(25), 3);

        assert!(obligation.deposited_value_usd == decimal::from(1000), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(100), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(500), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(25), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(50), 4);
        assert!(obligation.weighted_borrowed_value_upper_bound_usd == decimal::from(100), 4);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EObligationIsNotHealthy)]
    public fun test_withdraw_fail_unhealthy() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 50 * 1_000_000);

        withdraw<TEST_MARKET>(&mut obligation, &sui_reserve, 50 * 1_000_000_000 + 1);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EDepositNotFound)]
    public fun test_withdraw_fail_deposit_not_found() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 50 * 1_000_000);

        withdraw<TEST_MARKET>(&mut obligation, &usdc_reserve, 1);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_withdraw_happy() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        reserve::update_price_for_testing(
            &mut usdc_reserve, 
            &clock, 
            decimal::from(1), 
            decimal::from(2)
        );
        reserve::update_price_for_testing(
            &mut sui_reserve, 
            &clock, 
            decimal::from(10), 
            decimal::from(5)
        );

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 20 * 1_000_000);
        withdraw<TEST_MARKET>(&mut obligation, &sui_reserve, 20 * 1_000_000_000);

        std::debug::print(&obligation);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 80 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(800), 4);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(20 * 1_000_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from(2), 2);
        assert!(usdc_borrow.market_value == decimal::from(20), 3);

        assert!(obligation.deposited_value_usd == decimal::from(800), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(80), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(400), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(20), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(40), 4);
        assert!(obligation.weighted_borrowed_value_upper_bound_usd == decimal::from(80), 4);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_repay_happy() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        reserve::update_price_for_testing(
            &mut usdc_reserve, 
            &clock, 
            decimal::from(1), 
            decimal::from(2)
        );
        reserve::update_price_for_testing(
            &mut sui_reserve, 
            &clock, 
            decimal::from(10), 
            decimal::from(5)
        );

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 25 * 1_000_000);

        clock::set_for_testing(&mut clock, 1000);
        reserve::compound_interest(&mut usdc_reserve, &clock);

        repay<TEST_MARKET>(&mut obligation, &usdc_reserve, decimal::from(25 * 1_000_000));

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        // borrow was compounded by 1% so there should be borrows outstanding
        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(250_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from_percent(202), 2);
        assert!(usdc_borrow.market_value == decimal::from_percent(25), 3);

        assert!(obligation.deposited_value_usd == decimal::from(1000), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(100), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(500), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from_percent(25), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from_percent(50), 4);
        assert!(obligation.weighted_borrowed_value_upper_bound_usd == decimal::from(1), 4);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_repay_happy_2() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &sui_reserve, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &usdc_reserve, 100 * 1_000_000);


        clock::set_for_testing(&mut clock, 1000);
        reserve::compound_interest(&mut usdc_reserve, &clock);

        repay<TEST_MARKET>(&mut obligation, &usdc_reserve, decimal::from(500_000));

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        // borrow was compounded by 1% so there should be borrows outstanding
        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(101 * 1_000_000 - 500_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from_percent(202), 2);
        assert!(usdc_borrow.market_value == decimal::from_percent_u64(10_050), 3);

        assert!(obligation.deposited_value_usd == decimal::from(1000), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(200), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(500), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from_percent_u64(10_050), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from_percent_u64(20_100), 4);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0, location = reserve)] // price stale
    public fun test_refresh_fail_deposit_price_stale() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};
        use std::debug;
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000
        );

        clock::set_for_testing(&mut clock, 1000); 

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );
        debug::print(&obligation);

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0, location = reserve)] // price stale
    public fun test_refresh_fail_borrow_price_stale() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            100 * 1_000_000
        );

        clock::set_for_testing(&mut clock, 1000); 
        reserve::update_price_for_testing(
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock, 
            decimal::from(10), 
            decimal::from(10)
        );

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_refresh_happy() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );
        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            100 * 1_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            100 * 1_000_000
        );

        clock::set_for_testing(&mut clock, 1000); 
        reserve::update_price_for_testing(
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock, 
            decimal::from(10), 
            decimal::from(9)
        );
        reserve::update_price_for_testing(
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock, 
            decimal::from(1), 
            decimal::from(2)
        );

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );

        assert!(vector::length(&obligation.deposits) == 2, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        let usdc_deposit = vector::borrow(&obligation.deposits, 1);
        assert!(usdc_deposit.deposited_ctoken_amount == 100 * 1_000_000, 3);
        assert!(usdc_deposit.market_value == decimal::from(100), 4);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(101 * 1_000_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from_percent(202), 2);
        assert!(usdc_borrow.market_value == decimal::from(101), 3);

        std::debug::print(&obligation);
        assert!(obligation.deposited_value_usd == decimal::from(1100), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(230), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(580), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(101), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(202), 4);
        assert!(obligation.weighted_borrowed_value_upper_bound_usd == decimal::from(404), 4);

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EObligationIsNotLiquidatable)]
    public fun test_liquidate_fail_healthy() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            100 * 1_000_000
        );

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );
        liquidate<TEST_MARKET>(
            &mut obligation,
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_liquidate_happy_1() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            50 * 1_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDT>(&reserves),
            50 * 1_000_000
        );

        let config = {
            let builder = reserve_config::from(
                reserve::config(get_reserve<TEST_MARKET, TEST_SUI>(&reserves)), 
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_liquidation_bonus_bps(&mut builder, 1000);
            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };
        reserve::update_reserve_config(
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves), 
            config
        );

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );
        liquidate<TEST_MARKET>(
            &mut obligation,
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );

        assert!(vector::length(&obligation.deposits) == 1, 0);

        // $40 was liquidated with a 10% bonus = $44 = 4.4 sui => 95.6 sui remaining
        let sui_deposit = find_deposit(&obligation, get_reserve<TEST_MARKET, TEST_SUI>(&reserves));
        assert!(sui_deposit.deposited_ctoken_amount == 95 * 1_000_000_000 + 600_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(956), 4);

        assert!(vector::length(&obligation.borrows) == 2, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(10 * 1_000_000), 1);
        assert!(usdc_borrow.market_value == decimal::from(10), 3);

        let usdt_borrow = vector::borrow(&obligation.borrows, 1);
        assert!(usdt_borrow.borrowed_amount == decimal::from(50 * 1_000_000), 1);
        assert!(usdt_borrow.market_value == decimal::from(50), 3);

        assert!(obligation.deposited_value_usd == decimal::from(956), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(0), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(0), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(60), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(120), 4);

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_liquidate_happy_2() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};
        use std::debug;
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            1 * 1_000_000_000 + 100_000_000
        );
        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_ETH>(&reserves),
            2 * 100_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            100 * 1_000_000
        );

        let eth_reserve = get_reserve_mut<TEST_MARKET, TEST_ETH>(&mut reserves);
        let config = {
            let builder = reserve_config::from(
                reserve::config(eth_reserve),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);

            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };
        reserve::update_reserve_config(eth_reserve, config);


        let sui_reserve = get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves);
        let config = {
            let builder = reserve_config::from(
                reserve::config(sui_reserve),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_liquidation_bonus_bps(&mut builder, 1000);

            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };
        reserve::update_reserve_config(sui_reserve, config);

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );

        liquidate<TEST_MARKET>(
            &mut obligation,
            get_reserve<TEST_MARKET, TEST_USDC>(&reserves),
            get_reserve<TEST_MARKET, TEST_SUI>(&reserves),
            100 * 1_000_000_000
        );

        debug::print(&obligation);

        assert!(vector::length(&obligation.deposits) == 2, 0);

        // $40 was liquidated with a 10% bonus = $44 = 4.4 sui => 95.6 sui remaining
        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 0, 3);
        assert!(sui_deposit.market_value == decimal::from(0), 4);

        let eth_deposit = vector::borrow(&obligation.deposits, 1);
        assert!(eth_deposit.deposited_ctoken_amount == 2 * 100_000_000, 3);
        assert!(eth_deposit.market_value == decimal::from(4000), 4);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(90 * 1_000_000), 1);
        assert!(usdc_borrow.market_value == decimal::from(90), 3);

        assert!(obligation.deposited_value_usd == decimal::from(4000), 4000);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(0), 0);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(0), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(90), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(180), 4);

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }
}
