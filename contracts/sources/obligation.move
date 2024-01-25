module suilend::obligation {
    use sui::object::{Self, UID};
    use std::vector::{Self};
    use sui::tx_context::{TxContext};
    use suilend::reserve::{Self, Reserve, config};
    use suilend::reserve_config::{open_ltv, close_ltv, borrow_weight, liquidation_bonus};
    use sui::clock::{Clock};
    use suilend::decimal::{Self, Decimal, mul, add, sub, div, gt, lt, min, ceil, floor, le};

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

    struct RefreshedTicket has drop {}

    // update obligation's health value
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
            reserve::assert_price_is_fresh(deposit_reserve, clock);

            let market_value = reserve::ctoken_market_value(
                deposit_reserve,
                deposit.deposited_ctoken_amount
            );

            deposit.market_value = market_value;
            deposited_value_usd = add(deposited_value_usd, market_value);
            allowed_borrow_value_usd = add(
                allowed_borrow_value_usd,
                mul(
                    market_value,
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

        while (i < vector::length(&obligation.borrows)) {
            let borrow = vector::borrow_mut(&mut obligation.borrows, i);

            let borrow_reserve = vector::borrow_mut(reserves, borrow.reserve_id);
            reserve::compound_interest(borrow_reserve, clock);
            reserve::assert_price_is_fresh(borrow_reserve, clock);

            compound_interest(borrow, borrow_reserve);

            let market_value = reserve::market_value(borrow_reserve, borrow.borrowed_amount);

            borrow.market_value = market_value;
            unweighted_borrowed_value_usd = add(unweighted_borrowed_value_usd, market_value);
            weighted_borrowed_value_usd = add(
                weighted_borrowed_value_usd,
                mul(
                    market_value,
                    borrow_weight(config(borrow_reserve))
                )
            );

            i = i + 1;
        };

        obligation.unweighted_borrowed_value_usd = unweighted_borrowed_value_usd;
        obligation.weighted_borrowed_value_usd = weighted_borrowed_value_usd;

        RefreshedTicket {}
    }

    public(friend) fun deposit<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        let deposit = find_or_add_deposit(obligation, reserve::id(reserve));
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
                deposit_value,
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


    public(friend) fun borrow<P, T>(
        ticket: RefreshedTicket,
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        amount: u64,
    ) {
        let borrow = find_or_add_borrow(obligation, reserve::id(reserve));

        borrow.borrowed_amount = add(borrow.borrowed_amount, decimal::from(amount));

        // update health values
        let new_market_value = reserve::market_value(reserve, borrow.borrowed_amount);
        let diff = sub(new_market_value, borrow.market_value);

        borrow.market_value = new_market_value;
        obligation.unweighted_borrowed_value_usd = add(obligation.unweighted_borrowed_value_usd, diff);
        obligation.weighted_borrowed_value_usd = add(
            obligation.weighted_borrowed_value_usd, 
            mul(diff, borrow_weight(config(reserve)))
        );

        assert!(is_healthy(obligation), EObligationIsUnhealthy);
        let RefreshedTicket {} = ticket;
    }

    public(friend) fun repay<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        amount: Decimal,
    ) {
        let borrow_index = find_borrow_index(obligation, reserve::id(reserve));
        let borrow = vector::borrow_mut(&mut obligation.borrows, borrow_index);

        compound_interest(borrow, reserve);

        borrow.borrowed_amount = sub(borrow.borrowed_amount, amount);

        let repay_value = reserve::market_value(reserve, amount);

        // update other health values. note that we don't enforce price freshness here. this is purely
        // to make offchain accounting easier. any operation that requires price 
        // freshness (withdraw, borrow, liquidate) will refresh the obligation right before.
        // TODO: is it possible to underflow here? probably should do a saturating sub just in case.
        borrow.market_value = sub(borrow.market_value, repay_value);
        obligation.unweighted_borrowed_value_usd = sub(
            obligation.unweighted_borrowed_value_usd,
            repay_value
        );
        obligation.weighted_borrowed_value_usd = sub(
            obligation.weighted_borrowed_value_usd,
            mul(repay_value, borrow_weight(config(reserve)))
        );
    }

    fun withdraw_unchecked<P>(
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        let deposit_index = find_deposit_index(obligation, reserve::id(reserve));
        let deposit = vector::borrow_mut(&mut obligation.deposits, deposit_index);

        let withdraw_market_value = reserve::ctoken_market_value(reserve, ctoken_amount);

        // update health values
        deposit.market_value = sub(deposit.market_value, withdraw_market_value);
        deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount - ctoken_amount;

        obligation.deposited_value_usd = sub(obligation.deposited_value_usd, withdraw_market_value);
        obligation.allowed_borrow_value_usd = sub(
            obligation.allowed_borrow_value_usd,
            mul(
                withdraw_market_value,
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

    public(friend) fun withdraw<P>(
        ticket: RefreshedTicket,
        obligation: &mut Obligation<P>,
        reserve: &Reserve<P>,
        ctoken_amount: u64,
    ) {
        withdraw_unchecked(obligation, reserve, ctoken_amount);

        assert!(is_healthy(obligation), EObligationIsUnhealthy);
        let RefreshedTicket {} = ticket;
    }

    public(friend) fun liquidate<P>(
        _ticket: RefreshedTicket,
        obligation: &mut Obligation<P>,
        repay_reserve: &Reserve<P>,
        withdraw_reserve: &Reserve<P>,
        repay_amount: u64,
    ): (u64, u64) {
        assert!(is_unhealthy(obligation), EObligationIsHealthy);

        let borrow = find_borrow(obligation, reserve::id(repay_reserve));
        let deposit = find_deposit(obligation, reserve::id(withdraw_reserve));

        let repay_amount = min(
            mul(borrow.borrowed_amount, decimal::from_percent(CLOSE_FACTOR_PCT)),
            decimal::from(repay_amount)
        );

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
            final_withdraw_amount = floor(mul(
                decimal::from(deposit.deposited_ctoken_amount), 
                withdraw_pct));
        };

        repay(obligation, repay_reserve, final_settle_amount);
        withdraw_unchecked(obligation, withdraw_reserve, final_withdraw_amount);

        (final_withdraw_amount, final_repay_amount)
    }

    public fun is_healthy<P>(obligation: &Obligation<P>): bool {
        le(obligation.weighted_borrowed_value_usd, obligation.allowed_borrow_value_usd)
    }

    public fun is_unhealthy<P>(obligation: &Obligation<P>): bool {
        gt(obligation.unweighted_borrowed_value_usd, obligation.unhealthy_borrow_value_usd)
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
            // FIXME: this is incorrect
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

    #[test_only]
    use suilend::reserve_config::{ReserveConfig};

    #[test_only]
    public fun destroy_for_testing<P>(obligation: Obligation<P>) {
        let Obligation {
            id,
            owner: _,
            deposits,
            borrows,
            deposited_value_usd: _,
            allowed_borrow_value_usd: _,
            unhealthy_borrow_value_usd: _,
            unweighted_borrowed_value_usd: _,
            weighted_borrowed_value_usd: _,
        } = obligation;

        while (vector::length(&deposits) > 0) {
            let deposit = vector::pop_back(&mut deposits);
            destroy_deposit_for_testing<P>(deposit);
        };
        vector::destroy_empty(deposits);

        while (vector::length(&borrows) > 0) {
            let borrow = vector::pop_back(&mut borrows);
            destroy_borrow_for_testing<P>(borrow);
        };
        vector::destroy_empty(borrows);

        object::delete(id);
    }

    #[test_only]
    public fun destroy_deposit_for_testing<P>(deposit: Deposit<P>) {
        let Deposit {
            reserve_id: _,
            deposited_ctoken_amount: _,
            market_value: _,
        } = deposit;
    }

    #[test_only]
    public fun destroy_borrow_for_testing<P>(borrow: Borrow<P>) {
        let Borrow {
            reserve_id: _,
            borrowed_amount: _,
            cumulative_borrow_rate: _,
            market_value: _,
        } = borrow;
    }

    /* == Tests */
    #[test_only]
    struct ReserveArgs {
        id: u64,
        config: ReserveConfig,
        mint_decimals: u8,
        price: Decimal,
        price_last_update_timestamp_s: u64,
        available_amount: u64,
        ctoken_supply: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        interest_last_update_timestamp_s: u64,
    }

    #[test_only]
    struct TEST_MARKET {}

    use std::debug;
    use suilend::reserve_config::{Self};

    #[test_only]
    fun sui_reserve<P>(): Reserve<P> {
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
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 1);
                v
            }
        );

        reserve::create_for_testing<P>(
            0,
            config,
            9,
            decimal::from(10),
            0,
            0,
            0,
            decimal::from(0),
            decimal::from(1),
            0
        )
    }

    #[test_only]
    fun usdc_reserve<P>(): Reserve<P> {
        let config = reserve_config::create_reserve_config(
            // open ltv
            50,
            // close ltv
            80,
            // borrow weight bps
            10_000,
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
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 1);
                v
            }
        );

        reserve::create_for_testing<P>(
            1,
            config,
            6,
            decimal::from(1),
            0,
            0,
            0,
            decimal::from(0),
            decimal::from(1),
            0
        )
    }

    #[test]
    public fun test_deposit() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve();
        let sui_reserve = sui_reserve();

        let obligation = create_obligation<TEST_MARKET>(owner, test_scenario::ctx(&mut scenario));

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
        assert!(obligation.allowed_borrow_value_usd == decimal::from(300), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(660), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(0), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(0), 4);


        debug::print(&obligation);

        reserve::destroy_for_testing(usdc_reserve);
        reserve::destroy_for_testing(sui_reserve);
        destroy_for_testing(obligation);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_withdraw() {
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let usdc_reserve = usdc_reserve();
        let sui_reserve = sui_reserve();

        let obligation = create_obligation<TEST_MARKET>(owner, test_scenario::ctx(&mut scenario));

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
        assert!(obligation.allowed_borrow_value_usd == decimal::from(300), 1);
        assert!(obligation.unhealthy_borrow_value_usd == decimal::from(660), 2);
        assert!(obligation.unweighted_borrowed_value_usd == decimal::from(0), 3);
        assert!(obligation.weighted_borrowed_value_usd == decimal::from(0), 4);


        // debug::print(&obligation);

        reserve::destroy_for_testing(usdc_reserve);
        reserve::destroy_for_testing(sui_reserve);
        destroy_for_testing(obligation);
        test_scenario::end(scenario);
    }
}
