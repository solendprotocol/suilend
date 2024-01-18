module suilend::obligation {
    use sui::object::{Self, UID};
    use std::vector::{Self};
    use sui::tx_context::{TxContext};
    use suilend::reserve::{Self, Reserve};
    use std::debug;
    use sui::clock::{Clock};
    use suilend::decimal::{Self, Decimal, mul, add, sub, div, ge, gt, lt, min, ceil, floor};

    friend suilend::lending_market;

    /* errors */
    const EObligationIsUnhealthy: u64 = 0;
    const EObligationIsHealthy: u64 = 1;
    const EBorrowNotFound: u64 = 2;
    const EDepositNotFound: u64 = 3;

    /* constants */
    const CLOSE_FACTOR_PCT: u8 = 20;

    struct Obligation<phantom P> has key, store {
        id: UID,
        owner: address,

        deposits: vector<Deposit<P>>,
        borrows: vector<Borrow<P>>,

        // health stats
        deposited_value_usd: Decimal,
        allowed_borrow_value_usd: Decimal,
        unhealthy_borrow_value_usd: Decimal,

        unweighted_borrowed_value_usd: Decimal,
        weighted_borrowed_value_usd: Decimal,
    }

    struct Deposit<phantom P> has store {
        reserve_id: u64,
        deposited_ctoken_amount: u64,
        market_value: Decimal,
    }

    struct Borrow<phantom P> has store {
        reserve_id: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        market_value: Decimal
    }

    fun compound_interest<P>(borrow: &mut Borrow<P>, reserve: &Reserve<P>) {
        let new_cumulative_borrow_rate = reserve::cumulative_borrow_rate(reserve);

        let compounded_interest_rate = div(
            new_cumulative_borrow_rate,
            borrow.cumulative_borrow_rate
        );

        assert!(ge(compounded_interest_rate, decimal::from(1)), 0);

        borrow.borrowed_amount = mul(
            borrow.borrowed_amount,
            compounded_interest_rate
        );

        borrow.cumulative_borrow_rate = new_cumulative_borrow_rate;
    }

    public(friend) fun create_obligation<P>(owner: address, ctx: &mut TxContext): Obligation<P> {
        Obligation<P> {
            id: object::new(ctx),
            owner: owner,
            deposits: vector::empty(),
            borrows: vector::empty(),
            deposited_value_usd: decimal::from(0),
            unweighted_borrowed_value_usd: decimal::from(0),
            weighted_borrowed_value_usd: decimal::from(0),
            allowed_borrow_value_usd: decimal::from(0),
            unhealthy_borrow_value_usd: decimal::from(0)
        }
    }

    public(friend) fun deposit<P, T>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        let deposit = find_or_add_deposit(obligation, reserve::id(reserve));
        deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount + ctoken_amount;
    }

    fun find_deposit_index<P>(
        obligation: &Obligation<P>,
        reserve_id: u64,
    ): u64 {
        let i = 0;
        while (i < vector::length(&obligation.deposits)) {
            let deposit = vector::borrow(&obligation.deposits, i);
            if (deposit.reserve_id == reserve_id) {
                return i
            };

            i = i + 1;
        };

        i
    }

    fun find_borrow_index<P>(
        obligation: &Obligation<P>,
        reserve_id: u64,
    ): u64 {
        let i = 0;
        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow(&obligation.borrows, i);
            if (borrow.reserve_id == reserve_id) {
                return i
            };

            i = i + 1;
        };

        i
    }

    fun find_borrow_mut<P>(
        obligation: &mut Obligation<P>,
        reserve_id: u64,
    ): &mut Borrow<P> {
        let i = find_borrow_index(obligation, reserve_id);
        assert!(i < vector::length(&obligation.borrows), EBorrowNotFound);

        vector::borrow_mut(&mut obligation.borrows, i)
    }

    fun find_borrow<P>(
        obligation: &Obligation<P>,
        reserve_id: u64,
    ): &Borrow<P> {
        let i = find_borrow_index(obligation, reserve_id);
        assert!(i < vector::length(&obligation.borrows), EBorrowNotFound);

        vector::borrow(&obligation.borrows, i)
    }

    fun find_deposit_mut<P>(
        obligation: &mut Obligation<P>,
        reserve_id: u64,
    ): &mut Deposit<P> {
        let i = find_deposit_index(obligation, reserve_id);
        assert!(i < vector::length(&obligation.deposits), EDepositNotFound);

        vector::borrow_mut(&mut obligation.deposits, i)
    }

    fun find_deposit<P>(
        obligation: &Obligation<P>,
        reserve_id: u64,
    ): &Deposit<P> {
        let i = find_deposit_index(obligation, reserve_id);
        assert!(i < vector::length(&obligation.deposits), EDepositNotFound);

        vector::borrow(&obligation.deposits, i)
    }   

    fun find_or_add_borrow<P>(
        obligation: &mut Obligation<P>,
        reserve_id: u64,
    ): &mut Borrow<P> {
        let i = find_borrow_index(obligation, reserve_id);
        if (i < vector::length(&obligation.borrows)) {
            return vector::borrow_mut(&mut obligation.borrows, i)
        };

        let borrow = Borrow<P> {
            reserve_id: reserve_id,
            borrowed_amount: decimal::from(0),
            cumulative_borrow_rate: decimal::from(1),
            market_value: decimal::from(0)
        };

        vector::push_back(&mut obligation.borrows, borrow);
        let length = vector::length(&obligation.borrows);
        vector::borrow_mut(&mut obligation.borrows, length - 1)
    }

    fun find_or_add_deposit<P>(
        obligation: &mut Obligation<P>,
        reserve_id: u64,
    ): &mut Deposit<P> {
        let i = find_deposit_index(obligation, reserve_id);
        if (i < vector::length(&obligation.deposits)) {
            return vector::borrow_mut(&mut obligation.deposits, i)
        };

        let deposit = Deposit<P> {
            reserve_id: reserve_id,
            deposited_ctoken_amount: 0,
            market_value: decimal::from(0)
        };

        vector::push_back(&mut obligation.deposits, deposit);
        let length = vector::length(&obligation.deposits);
        vector::borrow_mut(&mut obligation.deposits, length - 1)
    }

    struct RefreshedTicket has drop {}

    public(friend) fun refresh<P>(
        obligation: &mut Obligation<P>,
        reserves: &mut vector<Reserve<P>>,
        clock: &Clock
    ): RefreshedTicket {
        let i = 0;
        let deposited_value_usd = decimal::from(0);
        let allowed_borrow_value_usd = decimal::from(0);
        let unhealthy_borrow_value_usd = decimal::from(0);

        while (i < vector::length(&obligation.deposits)) {
            let deposit = vector::borrow_mut(&mut obligation.deposits, i);

            let deposit_reserve = vector::borrow_mut(reserves, deposit.reserve_id);
            reserve::compound_interest(deposit_reserve, clock);

            let liquidity_amount = mul(
                    decimal::from(deposit.deposited_ctoken_amount),
                    reserve::ctoken_ratio(deposit_reserve)
            );
            let market_value = reserve::market_value(
                deposit_reserve,
                clock,
                liquidity_amount
            );

            deposit.market_value = market_value;
            deposited_value_usd = add(deposited_value_usd, market_value);
            allowed_borrow_value_usd = add(
                allowed_borrow_value_usd,
                mul(
                    market_value,
                    reserve::open_ltv(deposit_reserve)
                )
            );
            unhealthy_borrow_value_usd = add(
                unhealthy_borrow_value_usd,
                mul(
                    market_value,
                    reserve::close_ltv(deposit_reserve)
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

        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow_mut(&mut obligation.borrows, i);

            let borrow_reserve = vector::borrow_mut(reserves, borrow.reserve_id);
            reserve::compound_interest(borrow_reserve, clock);

            compound_interest(borrow, borrow_reserve);

            let market_value = reserve::market_value(borrow_reserve, clock, borrow.borrowed_amount);

            borrow.market_value = market_value;
            unweighted_borrowed_value_usd = add(unweighted_borrowed_value_usd, market_value);
            weighted_borrowed_value_usd = add(
                weighted_borrowed_value_usd,
                mul(
                    market_value,
                    reserve::borrow_weight(borrow_reserve)
                )
            );

            i = i + 1;
        };

        obligation.unweighted_borrowed_value_usd = unweighted_borrowed_value_usd;
        obligation.weighted_borrowed_value_usd = weighted_borrowed_value_usd;

        RefreshedTicket {}
    }

    public(friend) fun borrow<P, T>(
        ticket: RefreshedTicket,
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        clock: &Clock,
        amount: u64,
    ) {
        let borrow = find_or_add_borrow(obligation, reserve::id(reserve));

        borrow.borrowed_amount = add(borrow.borrowed_amount, decimal::from(amount));

        // update health values
        let new_market_value = reserve::market_value(reserve, clock, borrow.borrowed_amount);
        let diff = sub(new_market_value, borrow.market_value);

        borrow.market_value = new_market_value;
        obligation.unweighted_borrowed_value_usd = add(obligation.unweighted_borrowed_value_usd, diff);
        obligation.weighted_borrowed_value_usd = add(
            obligation.weighted_borrowed_value_usd, 
            mul(diff, reserve::borrow_weight(reserve))
        );

        assert!(is_healthy(obligation), EObligationIsUnhealthy);
        let RefreshedTicket {} = ticket;
    }

    public(friend) fun repay<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        amount: u64,
    ) {
        let borrow_index = find_borrow_index(obligation, reserve::id(reserve));
        let borrow = vector::borrow_mut(&mut obligation.borrows, borrow_index);

        compound_interest(borrow, reserve);

        borrow.borrowed_amount = sub(borrow.borrowed_amount, decimal::from(amount));
    }

    public(friend) fun withdraw<P, T>(
        ticket: RefreshedTicket,
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        clock: &Clock,
        ctoken_amount: u64,
    ) {
        let deposit_index = find_deposit_index(obligation, reserve::id(reserve));
        let deposit = vector::borrow_mut(&mut obligation.deposits, deposit_index);

        let liquidity_amount = mul(
            decimal::from(ctoken_amount),
            reserve::ctoken_ratio(reserve)
        );

        let withdraw_market_value = reserve::market_value(reserve, clock, liquidity_amount);

        // update health values
        deposit.market_value = sub(deposit.market_value, withdraw_market_value);
        deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount - ctoken_amount;

        obligation.deposited_value_usd = sub(obligation.deposited_value_usd, withdraw_market_value);
        obligation.allowed_borrow_value_usd = sub(
            obligation.allowed_borrow_value_usd,
            mul(
                withdraw_market_value,
                reserve::open_ltv(reserve)
            )
        );
        obligation.unhealthy_borrow_value_usd = sub(
            obligation.unhealthy_borrow_value_usd,
            mul(
                withdraw_market_value,
                reserve::close_ltv(reserve)
            )
        );

        assert!(is_healthy(obligation), EObligationIsUnhealthy);
        let RefreshedTicket {} = ticket;
    }

    public(friend) fun liquidate<P>(
        _ticket: RefreshedTicket,
        obligation: &mut Obligation<P>,
        repay_reserve: &Reserve<P>,
        withdraw_reserve: &Reserve<P>,
        clock: &Clock,
        repay_amount: u64,
    ): (u64, u64) {
        assert!(is_unhealthy(obligation), EObligationIsHealthy);

        let borrow = find_borrow(obligation, reserve::id(repay_reserve));
        let deposit = find_deposit(obligation, reserve::id(withdraw_reserve));

        let repay_amount = min(
            mul(borrow.borrowed_amount, decimal::from_percent(CLOSE_FACTOR_PCT)),
            decimal::from(repay_amount)
        );

        let repay_value = reserve::market_value(repay_reserve, clock, repay_amount);
        let withdraw_value = mul(
            repay_value, 
            add(decimal::from(1), reserve::liquidation_bonus(withdraw_reserve))
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
            final_withdraw_amount = floor(mul(
                decimal::from(deposit.deposited_ctoken_amount), 
                withdraw_pct));
        };

        {
            let borrow = find_borrow_mut(obligation, reserve::id(repay_reserve));
            borrow.borrowed_amount = sub(borrow.borrowed_amount, final_settle_amount);
        };

        {
            let deposit = find_deposit_mut(obligation, reserve::id(withdraw_reserve));
            deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount - final_withdraw_amount;
        };

        debug::print(&b"hi");
        debug::print(&final_repay_amount);
        debug::print(&final_withdraw_amount);
        (final_withdraw_amount, final_repay_amount)
    }

    const HEALTH_STATUS_HEALTHY: u64 = 0;
    const HEALTH_STATUS_RISKY: u64 = 1;
    const HEALTH_STATUS_UNHEALTHY: u64 = 2;

    // obligation must have been refreshed before calling this
    fun health<P>(obligation: &Obligation<P>): u64 {
        if (gt(obligation.unweighted_borrowed_value_usd, obligation.unhealthy_borrow_value_usd)) {
            return HEALTH_STATUS_UNHEALTHY
        };

        if (gt(obligation.weighted_borrowed_value_usd, obligation.allowed_borrow_value_usd)) {
            return HEALTH_STATUS_RISKY
        };

        HEALTH_STATUS_HEALTHY
    }

    public fun is_healthy<P>(obligation: &Obligation<P>): bool {
        health(obligation) == HEALTH_STATUS_HEALTHY
    }

    public fun is_unhealthy<P>(obligation: &Obligation<P>): bool {
        health(obligation) == HEALTH_STATUS_UNHEALTHY
    }
}
