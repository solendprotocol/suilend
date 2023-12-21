#[test_only]
module suilend::test_lm {
    use suilend::test_helpers::{
        create_lending_market,
        create_reserve_config,
        create_clock,
        add_reserve,
        create_obligation
    };
    use sui::test_scenario::{Self};
    use std::vector::{Self};
    use sui::clock::{Self, Clock};

    struct TEST_LM has drop {}

    struct SUI has drop {}
    struct USDC has drop {}

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

        add_reserve<TEST_LM, USDC>(
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
        test_scenario::return_to_address(user, obligation_owner_cap);

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}