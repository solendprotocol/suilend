#[test_only]
module suilend::test_lm {
    use suilend::test_helpers::{
        Self,
        create_lending_market,
        create_reserve_config,
        create_clock,
        add_reserve,
        create_obligation,
        deposit_reserve_liquidity,
        deposit_ctokens_into_obligation,
        borrow,
        withdraw,
        repay
    };
    use std::debug;
    use suilend::decimal::{Self, Decimal};
    use suilend::test_usdc::{Self, TEST_USDC};
    use suilend::test_sui::{Self, TEST_SUI};
    use suilend::lending_market::{Self, LendingMarket};
    use sui::test_scenario::{Self};
    use std::vector::{Self};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::transfer::{Self};
    use std::option::{Self};

    struct TEST_LM has drop {}

    #[test]
    fun test_create_lending_market() {
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let owner_cap = create_lending_market(&mut scenario, TEST_LM {}, owner);

        test_scenario::return_to_sender(&scenario, owner_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_reserve() {
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let clock = create_clock(&mut scenario, owner);

        let owner_cap = create_lending_market(&mut scenario, TEST_LM {}, owner);
        let config = create_reserve_config(
            &mut scenario,
            owner,
            50,
            80,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );

        test_scenario::next_tx(&mut scenario, owner);
        {
            test_usdc::create_currency(
                test_scenario::ctx(&mut scenario)
            );

        };

        add_reserve<TEST_LM, TEST_USDC>(
            &mut scenario,
            owner,
            &owner_cap,
            (1 as u256),
            config,
            &clock,
        );


        test_scenario::return_to_sender(&scenario, owner_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_obligation() {
        let owner = @0x26;
        let user = @0x27;

        let scenario = test_scenario::begin(owner);
        let clock = create_clock(&mut scenario, owner);

        let owner_cap = create_lending_market(&mut scenario, TEST_LM {}, owner);
        let obligation_owner_cap = create_obligation<TEST_LM>(&mut scenario, user);

        test_scenario::return_to_address(owner, owner_cap);

        clock::destroy_for_testing(clock);
        lending_market::destroy_for_testing(obligation_owner_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_deposit() {
        let owner = @0x26;
        let user = @0x27;

        let scenario = test_scenario::begin(owner);
        let clock = create_clock(&mut scenario, owner);

        test_scenario::next_tx(&mut scenario, owner);
        {
            test_usdc::create_currency(
                test_scenario::ctx(&mut scenario)
            );

        };

        let owner_cap = create_lending_market(&mut scenario, TEST_LM {}, owner);
        let obligation_owner_cap = create_obligation<TEST_LM>(&mut scenario, user);
        let config = create_reserve_config(
            &mut scenario,
            owner,
            50,
            80,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );

        add_reserve<TEST_LM, TEST_USDC>(
            &mut scenario,
            owner,
            &owner_cap,
            (1 as u256),
            config,
            &clock,
        );

        let usdc = coin::mint_for_testing<TEST_USDC>(100, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_reserve_liquidity<TEST_LM, TEST_USDC>(&mut scenario, user, &clock, usdc);
        assert!(coin::value(&ctokens) == 100, 0);

        deposit_ctokens_into_obligation<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            &obligation_owner_cap,
            ctokens,
        );

        test_scenario::return_to_address(owner, owner_cap);

        // coin::burn_for_testing(ctokens);
        clock::destroy_for_testing(clock);
        lending_market::destroy_for_testing(obligation_owner_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_borrow() {
        let owner = @0x26;
        let user = @0x27;

        let scenario = test_scenario::begin(owner);
        let clock = create_clock(&mut scenario, owner);

        test_scenario::next_tx(&mut scenario, owner);
        {
            test_usdc::create_currency(
                test_scenario::ctx(&mut scenario)
            );
            test_sui::create_currency(
                test_scenario::ctx(&mut scenario)
            );

        };

        let owner_cap = create_lending_market(&mut scenario, TEST_LM {}, owner);
        let obligation_owner_cap = create_obligation<TEST_LM>(&mut scenario, user);
        let config = create_reserve_config(
            &mut scenario,
            owner,
            50,
            80,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );

        add_reserve<TEST_LM, TEST_USDC>(
            &mut scenario,
            owner,
            &owner_cap,
            decimal::to_scaled_val(decimal::from(1)),
            config,
            &clock,
        );

        let config = create_reserve_config(
            &mut scenario,
            owner,
            50,
            80,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );
        add_reserve<TEST_LM, TEST_SUI>(
            &mut scenario,
            owner,
            &owner_cap,
            decimal::to_scaled_val(decimal::from(10)),
            config,
            &clock,
        );

        let usdc = coin::mint_for_testing<TEST_USDC>(1_000_000, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_reserve_liquidity<TEST_LM, TEST_USDC>(&mut scenario, user, &clock, usdc);
        assert!(coin::value(&ctokens) == 1_000_000, 0);

        deposit_ctokens_into_obligation<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            &obligation_owner_cap,
            ctokens,
        );

        let borrowed_usdc = borrow<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            &obligation_owner_cap,
            &clock,
            250_000
        );

        let coins = withdraw<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            &obligation_owner_cap,
            &clock,
            500_000
        );

        debug::print(&coins);

        repay<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            lending_market::obligation_id(&obligation_owner_cap),
            &clock,
            borrowed_usdc,
        );

        test_scenario::next_tx(&mut scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<TEST_LM>>(&scenario);
            lending_market::print_obligation(&lending_market, lending_market::obligation_id(&obligation_owner_cap));
            test_scenario::return_shared(lending_market);
        };

        test_scenario::return_to_address(owner, owner_cap);

        coin::burn_for_testing(coins);
        clock::destroy_for_testing(clock);
        lending_market::destroy_for_testing(obligation_owner_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_liquidate() {
        let owner = @0x26;
        let user = @0x27;
        let liquidator = @0x28;

        let scenario = test_scenario::begin(owner);
        let clock = create_clock(&mut scenario, owner);

        test_scenario::next_tx(&mut scenario, owner);
        {
            test_usdc::create_currency(
                test_scenario::ctx(&mut scenario)
            );
            test_sui::create_currency(
                test_scenario::ctx(&mut scenario)
            );

        };

        let owner_cap = create_lending_market(&mut scenario, TEST_LM {}, owner);
        let obligation_owner_cap = create_obligation<TEST_LM>(&mut scenario, user);
        let config = create_reserve_config(
            &mut scenario,
            owner,
            50,
            80,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );

        add_reserve<TEST_LM, TEST_USDC>(
            &mut scenario,
            owner,
            &owner_cap,
            decimal::to_scaled_val(decimal::from(1)),
            config,
            &clock,
        );

        let config = create_reserve_config(
            &mut scenario,
            owner,
            50,
            80,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );
        add_reserve<TEST_LM, TEST_SUI>(
            &mut scenario,
            owner,
            &owner_cap,
            decimal::to_scaled_val(decimal::from(10)),
            config,
            &clock,
        );

        let usdc = coin::mint_for_testing<TEST_USDC>(1_000_000, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_reserve_liquidity<TEST_LM, TEST_USDC>(&mut scenario, user, &clock, usdc);
        assert!(coin::value(&ctokens) == 1_000_000, 0);

        deposit_ctokens_into_obligation<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            &obligation_owner_cap,
            ctokens,
        );

        let borrowed_usdc = borrow<TEST_LM, TEST_USDC>(
            &mut scenario,
            user,
            &obligation_owner_cap,
            &clock,
            500_000
        );
        let coinz = coin::split(&mut borrowed_usdc, 50_000, test_scenario::ctx(&mut scenario));

        let config = create_reserve_config(
            &mut scenario,
            owner,
            0,
            0,
            10_000,
            1000,
            1000,
            10,
            200_000,
            10_000,
            vector::empty(),
            vector::empty(),
        );

        test_helpers::update_reserve_config<TEST_LM, TEST_USDC>(&mut scenario, owner, &owner_cap, config);

        let (leftover_repay_coins, withdrawn_coins) = test_helpers::liquidate<TEST_LM, TEST_USDC, TEST_USDC>(
            &mut scenario,
            lending_market::obligation_id(&obligation_owner_cap),
            liquidator,
            &clock,
            coinz 
        );

        debug::print(&withdrawn_coins);
        test_scenario::next_tx(&mut scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<TEST_LM>>(&scenario);
            lending_market::print_obligation(&lending_market, lending_market::obligation_id(&obligation_owner_cap));
            test_scenario::return_shared(lending_market);
        };

        test_scenario::return_to_address(owner, owner_cap);

        coin::burn_for_testing(withdrawn_coins);
        coin::burn_for_testing(leftover_repay_coins);
        coin::burn_for_testing(borrowed_usdc);
        clock::destroy_for_testing(clock);
        lending_market::destroy_for_testing(obligation_owner_cap);
        test_scenario::end(scenario);
    }
}
