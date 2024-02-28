module suilend::obligation {
    // === Imports ===
    use std::type_name::{TypeName, Self};
    use sui::object::{Self, UID};
    use sui::balance::{Balance};
    use std::vector::{Self};
    use sui::tx_context::{TxContext};
    use suilend::reserve::{Self, Reserve, config};
    use suilend::reserve_config::{
        open_ltv, 
        close_ltv, 
        borrow_weight, 
        liquidation_bonus, 
        protocol_liquidation_fee,
        isolated
    };
    use sui::clock::{Clock};
    use suilend::decimal::{Self, Decimal, mul, add, sub, div, gt, lt, min, ceil, floor, le, eq};
    use suilend::liquidity_mining::{Self, Farmer, IncentiveManager};

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
    const EIsolatedAssetViolation: u64 = 4;

    // === Constants ===
    const CLOSE_FACTOR_PCT: u8 = 20;

    // === Structs ===
    struct Obligation<phantom P> has key, store {
        id: UID,

        /// all deposits in the obligation. there is at most one deposit per coin type
        /// There should never be a deposit object with a zeroed amount
        deposits: vector<Deposit>,
        /// all borrows in the obligation. there is at most one deposit per coin type
        /// There should never be a borrow object with a zeroed amount
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
        super_unhealthy_borrow_value_usd: Decimal, // unused

        /// value of all borrows in USD
        unweighted_borrowed_value_usd: Decimal,
        /// weighted value of all borrows in USD. used when checking if an obligation is liquidatable
        weighted_borrowed_value_usd: Decimal,
        /// weighted value of all borrows in USD, but using the upper bound of the market value
        /// used to limit borrows and withdraws
        weighted_borrowed_value_upper_bound_usd: Decimal,

        borrowing_isolated_asset: bool,
        farmers: vector<Farmer>,

        /// unused
        bad_debt_usd: Decimal,
        /// unused
        closable: bool
    }

    struct Deposit has store {
        coin_type: TypeName,
        reserve_array_index: u64,
        deposited_ctoken_amount: u64,
        market_value: Decimal,
        farmer_index: u64,
        /// unused
        attributed_borrow_value: Decimal
    }

    struct Borrow has store {
        coin_type: TypeName,
        reserve_array_index: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        market_value: Decimal,
        farmer_index: u64
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
            unhealthy_borrow_value_usd: decimal::from(0),
            super_unhealthy_borrow_value_usd: decimal::from(0),
            borrowing_isolated_asset: false,
            farmers: vector::empty(),
            bad_debt_usd: decimal::from(0),
            closable: false
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

            let farmer = vector::borrow_mut(&mut obligation.farmers, deposit.farmer_index);
            liquidity_mining::update_farmer(
                reserve::deposits_incentive_manager_mut(deposit_reserve),
                farmer,
                clock
            );

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
        let borrowing_isolated_asset = false;

        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow_mut(&mut obligation.borrows, i);

            let borrow_reserve = vector::borrow_mut(reserves, borrow.reserve_array_index);
            reserve::compound_interest(borrow_reserve, clock);
            reserve::assert_price_is_fresh(borrow_reserve, clock);

            compound_debt(borrow, borrow_reserve);

            let farmer = vector::borrow_mut(&mut obligation.farmers, borrow.farmer_index);
            liquidity_mining::update_farmer(
                reserve::borrows_incentive_manager_mut(borrow_reserve),
                farmer,
                clock
            );

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

            if (isolated(config(borrow_reserve))) {
                borrowing_isolated_asset = true;
            };

            i = i + 1;
        };

        obligation.unweighted_borrowed_value_usd = unweighted_borrowed_value_usd;
        obligation.weighted_borrowed_value_usd = weighted_borrowed_value_usd;
        obligation.weighted_borrowed_value_upper_bound_usd = weighted_borrowed_value_upper_bound_usd;

        obligation.borrowing_isolated_asset = borrowing_isolated_asset;
    }

    /// Process a deposit action
    public(friend) fun deposit<P>(
        obligation: &mut Obligation<P>,
        reserve: &mut Reserve<P>,
        clock: &Clock,
        ctoken_amount: u64,
    ) {
        let deposit_index = find_or_add_deposit(obligation, reserve, clock);
        let deposit = vector::borrow_mut(&mut obligation.deposits, deposit_index);

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

        let farmer = vector::borrow_mut(&mut obligation.farmers, deposit.farmer_index);
        liquidity_mining::change_farmer_share(
            reserve::deposits_incentive_manager_mut(reserve),
            farmer,
            deposit.deposited_ctoken_amount,
            clock
        );
    }

    /// Process a borrow action. Makes sure that the obligation is healthy after the borrow.
    public(friend) fun borrow<P>(
        obligation: &mut Obligation<P>,
        reserve: &mut Reserve<P>,
        clock: &Clock,
        amount: u64,
    ) {
        let borrow_index = find_or_add_borrow(obligation, reserve, clock);
        let borrow = vector::borrow_mut(&mut obligation.borrows, borrow_index);

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

        let farmer = vector::borrow_mut(&mut obligation.farmers, borrow.farmer_index);
        liquidity_mining::change_farmer_share(
            reserve::borrows_incentive_manager_mut(reserve),
            farmer,
            liability_shares(borrow),
            clock
        );

        assert!(is_healthy(obligation), EObligationIsNotHealthy);

        if (isolated(config(reserve)) || obligation.borrowing_isolated_asset) {
            assert!(vector::length(&obligation.borrows) == 1, EIsolatedAssetViolation);
        };
    }

    /// Process a repay action. The reserve's interest must have been refreshed before calling this.
    public(friend) fun repay<P>(
        obligation: &mut Obligation<P>,
        reserve: &mut Reserve<P>,
        clock: &Clock,
        max_repay_amount: Decimal,
    ): u64 {
        let borrow_index = find_borrow_index(obligation, reserve);
        assert!(borrow_index < vector::length(&obligation.borrows), EBorrowNotFound);
        let borrow = vector::borrow_mut(&mut obligation.borrows, borrow_index);

        let old_borrow_amount = borrow.borrowed_amount;
        compound_debt(borrow, reserve);

        let repay_amount = min(max_repay_amount, borrow.borrowed_amount);

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
        };

        let farmer = vector::borrow_mut(&mut obligation.farmers, borrow.farmer_index);
        liquidity_mining::update_farmer(
            reserve::borrows_incentive_manager_mut(reserve),
            farmer,
            clock
        );

        liquidity_mining::change_farmer_share(
            reserve::borrows_incentive_manager_mut(reserve),
            farmer,
            liability_shares(borrow),
            clock
        );

        if (eq(borrow.borrowed_amount, decimal::from(0))) {
            let Borrow { 
                coin_type: _, 
                reserve_array_index: _,
                borrowed_amount: _,
                cumulative_borrow_rate: _,
                market_value: _,
                farmer_index: _
            }  = vector::remove(&mut obligation.borrows, borrow_index);
        };

        ceil(repay_amount)
    }

    /// Process a withdraw action. Makes sure that the obligation is healthy after the withdraw.
    public(friend) fun withdraw<P>(
        obligation: &mut Obligation<P>,
        reserve: &mut Reserve<P>,
        clock: &Clock,
        ctoken_amount: u64,
    ) {
        withdraw_unchecked(obligation, reserve, clock, ctoken_amount);

        assert!(is_healthy(obligation), EObligationIsNotHealthy);
    }

    /// Process a liquidate action.
    /// Returns the amount of ctokens to withdraw, and the amount of tokens to repay.
    public(friend) fun liquidate<P>(
        obligation: &mut Obligation<P>,
        reserves: &mut vector<Reserve<P>>,
        repay_reserve_array_index: u64,
        withdraw_reserve_array_index: u64,
        clock: &Clock,
        repay_amount: u64,
    ): (u64, u64) {
        assert!(is_liquidatable(obligation), EObligationIsNotLiquidatable);

        let repay_reserve = vector::borrow(reserves, repay_reserve_array_index);
        let withdraw_reserve = vector::borrow(reserves, withdraw_reserve_array_index);
        let borrow = find_borrow(obligation, repay_reserve);
        let deposit = find_deposit(obligation, withdraw_reserve);

        // invariant: repay_amount <= borrow.borrowed_amount
        let repay_amount = if (le(borrow.market_value, decimal::from(1))) {
            // full liquidation
            borrow.borrowed_amount
        }
        else { // partial liquidation
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
        let bonus = add(
            liquidation_bonus(config(withdraw_reserve)),
            protocol_liquidation_fee(config(withdraw_reserve))
        );

        let withdraw_value = mul(
            repay_value, 
            add(decimal::from(1), bonus)
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

        repay(
            obligation, 
            vector::borrow_mut(reserves, repay_reserve_array_index), 
            clock, 
            final_settle_amount
        );
        withdraw_unchecked(
            obligation, 
            vector::borrow_mut(reserves, withdraw_reserve_array_index), 
            clock, 
            final_withdraw_amount
        );

        (final_withdraw_amount, final_repay_amount)
    }

    public(friend) fun claim_rewards<P, T>(
        obligation: &mut Obligation<P>,
        incentive_manager: &mut IncentiveManager,
        clock: &Clock,
        reward_index: u64,
    ): Balance<T> {

        let farmer_index = find_farmer_index(obligation, incentive_manager);
        let farmer = vector::borrow_mut(&mut obligation.farmers, farmer_index);

        liquidity_mining::update_incentive_manager(incentive_manager, clock);
        liquidity_mining::update_farmer(incentive_manager, farmer, clock);
        liquidity_mining::claim_rewards<T>(incentive_manager, farmer, clock, reward_index)
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
    fun liability_shares(borrow: &Borrow): u64 {
        floor(div(
            borrow.borrowed_amount,
            borrow.cumulative_borrow_rate
        ))
    }

    /// Withdraw without checking if the obligation is healthy.
    fun withdraw_unchecked<P>(
        obligation: &mut Obligation<P>,
        reserve: &mut Reserve<P>,
        clock: &Clock,
        ctoken_amount: u64,
    ) {
        let deposit_index = find_deposit_index(obligation, reserve);
        assert!(deposit_index < vector::length(&obligation.deposits), EDepositNotFound);
        let deposit = vector::borrow_mut(&mut obligation.deposits, deposit_index);

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

        let farmer = vector::borrow_mut(&mut obligation.farmers, deposit.farmer_index);
        liquidity_mining::change_farmer_share(
            reserve::deposits_incentive_manager_mut(reserve),
            farmer,
            deposit.deposited_ctoken_amount,
            clock
        );

        if (deposit.deposited_ctoken_amount == 0) {
            let Deposit { 
                coin_type: _,
                reserve_array_index: _,
                deposited_ctoken_amount: _,
                market_value: _,
                attributed_borrow_value: _,
                farmer_index: _
            } = vector::remove(&mut obligation.deposits, deposit_index);
        };
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

    fun find_borrow<P>(
        obligation: &Obligation<P>,
        reserve: &Reserve<P>,
    ): &Borrow {
        let i = find_borrow_index(obligation, reserve);
        assert!(i < vector::length(&obligation.borrows), EBorrowNotFound);

        vector::borrow(&obligation.borrows, i)
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
        reserve: &mut Reserve<P>,
        clock: &Clock
    ): u64 {
        let i = find_borrow_index(obligation, reserve);
        if (i < vector::length(&obligation.borrows)) {
            return i
        };

        let (farmer_index, _) = find_or_add_farmer(
            obligation,
            reserve::borrows_incentive_manager_mut(reserve),
            clock
        );

        let borrow = Borrow {
            coin_type: reserve::coin_type(reserve),
            reserve_array_index: reserve::array_index(reserve),
            borrowed_amount: decimal::from(0),
            cumulative_borrow_rate: reserve::cumulative_borrow_rate(reserve),
            market_value: decimal::from(0),
            farmer_index
        };

        vector::push_back(&mut obligation.borrows, borrow);
        vector::length(&obligation.borrows) - 1
    }

    fun find_or_add_deposit<P>(
        obligation: &mut Obligation<P>,
        reserve: &mut Reserve<P>,
        clock: &Clock
    ): u64 {
        let i = find_deposit_index(obligation, reserve);
        if (i < vector::length(&obligation.deposits)) {
            return i
        };

        let (farmer_index, _) = find_or_add_farmer(
            obligation,
            reserve::deposits_incentive_manager_mut(reserve),
            clock
        );

        let deposit = Deposit {
            coin_type: reserve::coin_type(reserve),
            reserve_array_index: reserve::array_index(reserve),
            deposited_ctoken_amount: 0,
            market_value: decimal::from(0),
            farmer_index,
            attributed_borrow_value: decimal::from(0)
        };

        vector::push_back(&mut obligation.deposits, deposit);
        vector::length(&obligation.deposits) - 1
    }

    fun find_farmer_index<P>(
        obligation: &Obligation<P>,
        incentive_manager: &IncentiveManager,
    ): u64 {
        let i = 0;
        while (i < vector::length(&obligation.farmers)) {
            let farmer = vector::borrow(&obligation.farmers, i);
            if (liquidity_mining::incentive_manager_id(farmer) == object::id(incentive_manager)) {
                return i
            };

            i = i + 1;
        };

        i
    }

    fun find_or_add_farmer<P>(
        obligation: &mut Obligation<P>,
        incentive_manager: &mut IncentiveManager,
        clock: &Clock
    ): (u64, &mut Farmer) {
        let i = find_farmer_index(obligation, incentive_manager);
        if (i < vector::length(&obligation.farmers)) {
            return (i, vector::borrow_mut(&mut obligation.farmers, i))
        };

        let farmer = liquidity_mining::new_farmer(incentive_manager, clock);
        vector::push_back(&mut obligation.farmers, farmer);
        let length = vector::length(&obligation.farmers);

        (length - 1, vector::borrow_mut(&mut obligation.farmers, length - 1))
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
    use suilend::reserve_config::{Self, default_reserve_config};

    #[test_only]
    fun sui_reserve<P>(scenario: &mut Scenario): Reserve<P> {
        let config = default_reserve_config();
        let builder = reserve_config::from(&config, test_scenario::ctx(scenario));
        reserve_config::set_open_ltv_pct(&mut builder, 20);
        reserve_config::set_close_ltv_pct(&mut builder, 50);
        reserve_config::set_max_close_ltv_pct(&mut builder, 50);
        reserve_config::set_interest_rate_utils(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 0);
            vector::push_back(&mut v, 100);
            v
        });
        reserve_config::set_interest_rate_aprs(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 31536000 * 4);
            vector::push_back(&mut v, 31536000 * 8);
            v
        });

        sui::test_utils::destroy(config);
        let config = reserve_config::build(builder, test_scenario::ctx(scenario));
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
        let config = default_reserve_config();
        let builder = reserve_config::from(&config, test_scenario::ctx(scenario));
        reserve_config::set_open_ltv_pct(&mut builder, 50);
        reserve_config::set_close_ltv_pct(&mut builder, 80);
        reserve_config::set_max_close_ltv_pct(&mut builder, 80);
        reserve_config::set_borrow_weight_bps(&mut builder, 20_000);
        reserve_config::set_interest_rate_utils(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 0);
            vector::push_back(&mut v, 100);
            v
        });
        reserve_config::set_interest_rate_aprs(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 3153600000);
            vector::push_back(&mut v, 3153600000 * 2);
            v
        });

        sui::test_utils::destroy(config);
        let config = reserve_config::build(builder, test_scenario::ctx(scenario));

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
        let config = default_reserve_config();
        let builder = reserve_config::from(&config, test_scenario::ctx(scenario));
        reserve_config::set_open_ltv_pct(&mut builder, 50);
        reserve_config::set_close_ltv_pct(&mut builder, 80);
        reserve_config::set_max_close_ltv_pct(&mut builder, 80);
        reserve_config::set_borrow_weight_bps(&mut builder, 20_000);
        reserve_config::set_interest_rate_utils(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 0);
            vector::push_back(&mut v, 100);
            v
        });
        reserve_config::set_interest_rate_aprs(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 3153600000);
            vector::push_back(&mut v, 3153600000 * 2);

            v
        });

        sui::test_utils::destroy(config);
        let config = reserve_config::build(builder, test_scenario::ctx(scenario));

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
        let config = default_reserve_config();
        let builder = reserve_config::from(&config, test_scenario::ctx(scenario));
        reserve_config::set_open_ltv_pct(&mut builder, 10);
        reserve_config::set_close_ltv_pct(&mut builder, 20);
        reserve_config::set_max_close_ltv_pct(&mut builder, 20);
        reserve_config::set_borrow_weight_bps(&mut builder, 30_000);
        reserve_config::set_interest_rate_utils(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 0);
            vector::push_back(&mut v, 100);
            v
        });
        reserve_config::set_interest_rate_aprs(&mut builder, {
            let v = vector::empty();
            vector::push_back(&mut v, 3153600000 * 10);
            vector::push_back(&mut v, 3153600000 * 20);

            v
        });

        sui::test_utils::destroy(config);
        let config = reserve_config::build(builder, test_scenario::ctx(scenario));

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

        deposit<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 100 * 1_000_000);
        deposit<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 100 * 1_000_000);
        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);

        assert!(vector::length(&obligation.deposits) == 2, 0);

        let usdc_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(usdc_deposit.deposited_ctoken_amount == 200 * 1_000_000, 1);
        assert!(usdc_deposit.market_value == decimal::from(200), 2);

        let farmer = vector::borrow(&obligation.farmers, usdc_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 200 * 1_000_000, 5);

        let sui_deposit = vector::borrow(&obligation.deposits, 1);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000_000, 6);

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
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 200 * 1_000_000 + 1);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        sui::test_utils::destroy(clock);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_borrow_isolated_happy() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );

        let config = {
            let builder = reserve_config::from(
                config(get_reserve<TEST_MARKET, TEST_USDC>(&reserves)),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_isolated(&mut builder, true);
            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };

        reserve::update_reserve_config(
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            config
        );

        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves), 
            &clock,
            1
        );

        refresh<TEST_MARKET>(&mut obligation, &mut reserves, &clock);

        // this fails
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves), 
            &clock, 
            1
        );

        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(reserves);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EIsolatedAssetViolation)]
    public fun test_borrow_isolated_fail() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );

        let config = {
            let builder = reserve_config::from(
                config(get_reserve<TEST_MARKET, TEST_USDC>(&reserves)),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_isolated(&mut builder, true);
            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };

        reserve::update_reserve_config(
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            config
        );

        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves), 
            &clock,
            1
        );

        refresh<TEST_MARKET>(&mut obligation, &mut reserves, &clock);

        // this fails
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves), 
            &clock, 
            1
        );

        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(reserves);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EIsolatedAssetViolation)]
    public fun test_borrow_isolated_fail_2() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );

        let config = {
            let builder = reserve_config::from(
                config(get_reserve<TEST_MARKET, TEST_USDC>(&reserves)),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_isolated(&mut builder, true);
            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };

        reserve::update_reserve_config(
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            config
        );

        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves), 
            &clock,
            1
        );

        refresh<TEST_MARKET>(&mut obligation, &mut reserves, &clock);

        // this fails
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves), 
            &clock,
            1
        );

        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(reserves);
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

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 12_500_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 12_500_000);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000_000, 3);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(25 * 1_000_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from(2), 2);
        assert!(usdc_borrow.market_value == decimal::from(25), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 25 * 1_000_000 / 2, 4);

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
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 50 * 1_000_000);

        withdraw<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 50 * 1_000_000_000 + 1);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        sui::test_utils::destroy(clock);
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
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 50 * 1_000_000);

        withdraw<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 1);

        sui::test_utils::destroy(usdc_reserve);
        sui::test_utils::destroy(sui_reserve);
        sui::test_utils::destroy(obligation);
        sui::test_utils::destroy(clock);
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

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 20 * 1_000_000);
        withdraw<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 20 * 1_000_000_000);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 80 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(800), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 80 * 1_000_000_000, 3);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(20 * 1_000_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from(2), 2);
        assert!(usdc_borrow.market_value == decimal::from(20), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 20 * 1_000_000 / 2, 4);

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

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 25 * 1_000_000);

        clock::set_for_testing(&mut clock, 1000);
        reserve::compound_interest(&mut usdc_reserve, &clock);

        let repay_amount = repay<TEST_MARKET>(
            &mut obligation, 
            &mut usdc_reserve, 
            &clock, 
            decimal::from(25 * 1_000_000)
        );
        assert!(repay_amount == 25 * 1_000_000, 0);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000_000, 5);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        // borrow was compounded by 1% so there should be borrows outstanding
        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(250_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from_percent(202), 2);
        assert!(usdc_borrow.market_value == decimal::from_percent(25), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        // 250_000 / 2.02 = 123762.376238
        assert!(liquidity_mining::shares(farmer) == 123_762, 5);

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

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 100 * 1_000_000);

        clock::set_for_testing(&mut clock, 1000);
        reserve::compound_interest(&mut usdc_reserve, &clock);

        let repay_amount = repay<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, decimal::from(500_000));
        assert!(repay_amount == 500_000, 0);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000_000, 5);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        // borrow was compounded by 1% so there should be borrows outstanding
        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(101 * 1_000_000 - 500_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from_percent(202), 2);
        assert!(usdc_borrow.market_value == decimal::from_percent_u64(10_050), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        // (101 * 1e6 - 500_000) / 2.02 == 49752475.2475
        assert!(liquidity_mining::shares(farmer) == 49752475, 5);

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
    public fun test_repay_max() {
        use sui::test_scenario::{Self};
        use sui::clock::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let usdc_reserve = usdc_reserve(&mut scenario);
        let sui_reserve = sui_reserve(&mut scenario);

        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(&mut obligation, &mut sui_reserve, &clock, 100 * 1_000_000_000);
        borrow<TEST_MARKET>(&mut obligation, &mut usdc_reserve, &clock, 100 * 1_000_000);


        let repay_amount = repay<TEST_MARKET>(
            &mut obligation, 
            &mut usdc_reserve, 
            &clock,
            decimal::from(101 * 1_000_000)
        );
        assert!(repay_amount == 100 * 1_000_000, 0);

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 100 * 1_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(1000), 4);

        assert!(vector::length(&obligation.borrows) == 0, 0);

        let farmer_index = find_farmer_index(
            &obligation, 
            reserve::borrows_incentive_manager_mut(&mut usdc_reserve)
        );
        let farmer = vector::borrow(&obligation.farmers, farmer_index);
        assert!(liquidity_mining::shares(farmer) == 0, 0);

        assert!(obligation.deposited_value_usd == decimal::from(1000), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(200), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(500), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from_percent_u64(0), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from_percent_u64(0), 4);

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
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000
        );

        clock::set_for_testing(&mut clock, 1000); 

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
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
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
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );
        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
            100 * 1_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
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

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000_000, 5);
        assert!(liquidity_mining::last_update_time_ms(farmer) == 1000, 6);

        let usdc_deposit = vector::borrow(&obligation.deposits, 1);
        assert!(usdc_deposit.deposited_ctoken_amount == 100 * 1_000_000, 3);
        assert!(usdc_deposit.market_value == decimal::from(100), 4);

        let farmer = vector::borrow(&obligation.farmers, usdc_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000, 5);
        assert!(liquidity_mining::last_update_time_ms(farmer) == 1000, 6);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(101 * 1_000_000), 1);
        assert!(usdc_borrow.cumulative_borrow_rate == decimal::from_percent(202), 2);
        assert!(usdc_borrow.market_value == decimal::from(101), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 100 * 1_000_000 / 2, 5);
        assert!(liquidity_mining::last_update_time_ms(farmer) == 1000, 6);

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
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
            100 * 1_000_000
        );

        refresh<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            &clock
        );
        liquidate<TEST_MARKET>(
            &mut obligation,
            &mut reserves,
            0,
            1,
            &clock,
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
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
            50 * 1_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDT>(&mut reserves),
            &clock,
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
            reserve_config::set_max_liquidation_bonus_bps(&mut builder, 1000);
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
            &mut reserves,
            1,
            0,
            &clock,
            100 * 1_000_000_000
        );

        assert!(vector::length(&obligation.deposits) == 1, 0);

        // $40 was liquidated with a 10% bonus = $44 = 4.4 sui => 95.6 sui remaining
        let sui_deposit = find_deposit(&obligation, get_reserve<TEST_MARKET, TEST_SUI>(&reserves));
        assert!(sui_deposit.deposited_ctoken_amount == 95 * 1_000_000_000 + 600_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(956), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 95 * 1_000_000_000 + 600_000_000, 5);

        assert!(vector::length(&obligation.borrows) == 2, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(10 * 1_000_000), 1);
        assert!(usdc_borrow.market_value == decimal::from(10), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 10 * 1_000_000 / 2, 5);

        let usdt_borrow = vector::borrow(&obligation.borrows, 1);
        assert!(usdt_borrow.borrowed_amount == decimal::from(50 * 1_000_000), 1);
        assert!(usdt_borrow.market_value == decimal::from(50), 3);

        let farmer = vector::borrow(&obligation.farmers, usdt_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 50 * 1_000_000 / 2, 5);

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
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 0); 

        let reserves = reserves<TEST_MARKET>(&mut scenario);
        let obligation = create_obligation<TEST_MARKET>(test_scenario::ctx(&mut scenario));

        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            1 * 1_000_000_000 + 100_000_000
        );
        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_ETH>(&mut reserves),
            &clock,
            2 * 100_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
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
            reserve_config::set_max_liquidation_bonus_bps(&mut builder, 1000);

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
            &mut reserves,
            1,
            0,
            &clock,
            100 * 1_000_000_000
        );

        assert!(vector::length(&obligation.deposits) == 1, 0);

        let farmer_index = find_farmer_index(
            &obligation, 
            reserve::deposits_incentive_manager_mut(get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves))
        );
        let farmer = vector::borrow(&obligation.farmers, farmer_index);
        assert!(liquidity_mining::shares(farmer) == 0, 5);

        let eth_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(eth_deposit.deposited_ctoken_amount == 2 * 100_000_000, 3);
        assert!(eth_deposit.market_value == decimal::from(4000), 4);

        let farmer = vector::borrow(&obligation.farmers, eth_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 2 * 100_000_000, 5);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(90 * 1_000_000), 1);
        assert!(usdc_borrow.market_value == decimal::from(90), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 90 * 1_000_000 / 2, 5);

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

    #[test]
    public fun test_liquidate_full_1() {
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
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            100 * 1_000_000_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
            1 * 1_000_000
        );

        let config = {
            let builder = reserve_config::from(
                reserve::config(get_reserve<TEST_MARKET, TEST_SUI>(&reserves)), 
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_liquidation_bonus_bps(&mut builder, 1000);
            reserve_config::set_max_liquidation_bonus_bps(&mut builder, 1000);
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
            &mut reserves,
            1,
            0,
            &clock,
            1_000_000_000
        );

        assert!(vector::length(&obligation.deposits) == 1, 0);

        // $1 was liquidated with a 10% bonus = $1.1 => 0.11 sui => 99.89 sui remaining
        let sui_deposit = find_deposit(&obligation, get_reserve<TEST_MARKET, TEST_SUI>(&reserves));
        assert!(sui_deposit.deposited_ctoken_amount == 99 * 1_000_000_000 + 890_000_000, 3);
        assert!(sui_deposit.market_value == add(decimal::from(998), decimal::from_percent(90)), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 99 * 1_000_000_000 + 890_000_000, 5);

        assert!(vector::length(&obligation.borrows) == 0, 0);

        let farmer_index = find_farmer_index(
            &obligation, 
            reserve::borrows_incentive_manager_mut(get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves))
        );
        let farmer = vector::borrow(&obligation.farmers, farmer_index);
        assert!(liquidity_mining::shares(farmer) == 0, 5);

        assert!(obligation.deposited_value_usd == add(decimal::from(998), decimal::from_percent(90)), 0);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(0), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(0), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(0), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(0), 4);

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_liquidate_full_2() {
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
            get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves),
            &clock,
            10 * 1_000_000_000
        );
        deposit<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
            550_000
        );
        borrow<TEST_MARKET>(
            &mut obligation, 
            get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves),
            &clock,
            10 * 1_000_000
        );

        let usdc_reserve = get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves);
        let config = {
            let builder = reserve_config::from(
                reserve::config(usdc_reserve),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_liquidation_bonus_bps(&mut builder, 1000);
            reserve_config::set_max_liquidation_bonus_bps(&mut builder, 1000);
            reserve_config::set_protocol_liquidation_fee_bps(&mut builder, 0);

            reserve_config::build(builder, test_scenario::ctx(&mut scenario))
        };
        reserve::update_reserve_config(usdc_reserve, config);


        let sui_reserve = get_reserve_mut<TEST_MARKET, TEST_SUI>(&mut reserves);
        let config = {
            let builder = reserve_config::from(
                reserve::config(sui_reserve),
                test_scenario::ctx(&mut scenario)
            );
            reserve_config::set_open_ltv_pct(&mut builder, 0);
            reserve_config::set_close_ltv_pct(&mut builder, 0);
            reserve_config::set_liquidation_bonus_bps(&mut builder, 1000);
            reserve_config::set_max_liquidation_bonus_bps(&mut builder, 1000);

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
            &mut reserves,
            1,
            1,
            &clock,
            100 * 1_000_000_000
        );

        assert!(vector::length(&obligation.deposits) == 1, 0);

        // unchanged
        let sui_deposit = vector::borrow(&obligation.deposits, 0);
        assert!(sui_deposit.deposited_ctoken_amount == 10_000_000_000, 3);
        assert!(sui_deposit.market_value == decimal::from(100), 4);

        let farmer = vector::borrow(&obligation.farmers, sui_deposit.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 10_000_000_000, 5);

        let farmer_index = find_farmer_index(
            &obligation, 
            reserve::deposits_incentive_manager_mut(get_reserve_mut<TEST_MARKET, TEST_USDC>(&mut reserves))
        );
        let farmer = vector::borrow(&obligation.farmers, farmer_index);
        assert!(liquidity_mining::shares(farmer) == 0, 5);

        assert!(vector::length(&obligation.borrows) == 1, 0);

        let usdc_borrow = vector::borrow(&obligation.borrows, 0);
        assert!(usdc_borrow.borrowed_amount == decimal::from(9_500_000), 1);
        assert!(usdc_borrow.market_value == decimal::from_percent_u64(950), 3);

        let farmer = vector::borrow(&obligation.farmers, usdc_borrow.farmer_index);
        assert!(liquidity_mining::shares(farmer) == 9_500_000 / 2, 5);

        assert!(obligation.deposited_value_usd == decimal::from(100), 4000);
        assert!(obligation.allowed_borrow_value_usd == decimal::from(0), 0);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(0), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from_percent_u64(950), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(19), 4);

        test_utils::destroy(reserves);
        clock::destroy_for_testing(clock);
        sui::test_utils::destroy(obligation);
        test_scenario::end(scenario);
    }
}
