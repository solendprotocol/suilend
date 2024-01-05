#[test_only]
/// Various helper functions to abstract away all the object stuff
module suilend::test_helpers {
    use sui::test_scenario::{Self, Scenario};
    use suilend::lending_market::{
        Self,
        LendingMarket, 
        LendingMarketOwnerCap, 
        ObligationOwnerCap
    };
    use sui::clock::{Self, Clock};
    use suilend::reserve::{
        Self,
        ReserveConfig,
        CToken
    };
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin, CoinMetadata};
    use std::option::{Self, Option};
    use std::vector::{Self};
    use sui::object::{Self, ID};

    public fun create_lending_market<P: drop>(scenario: &mut Scenario, witness: P, owner: address): LendingMarketOwnerCap<P> {
        test_scenario::next_tx(scenario, owner);
        {
            lending_market::create_lending_market<P>(
                witness,
                test_scenario::ctx(scenario)
            );
        };

        test_scenario::next_tx(scenario, owner);
        {
            test_scenario::take_from_sender<LendingMarketOwnerCap<P>>(scenario)
        }
    }

    public fun create_reserve_config(
        scenario: &mut Scenario, 
        owner: address,
        open_ltv_pct: u8, 
        close_ltv_pct: u8, 
        borrow_weight_bps: u64, 
        deposit_limit: u64, 
        borrow_limit: u64, 
        borrow_fee_bps: u64, 
        spread_fee_bps: u64, 
        liquidation_fee_bps: u64, 
        interest_rate_utils: vector<u8>,
        interest_rate_aprs: vector<u64>,
    ): ReserveConfig {
        test_scenario::next_tx(scenario, owner);
        {
            reserve::create_reserve_config(
                open_ltv_pct, 
                close_ltv_pct, 
                borrow_weight_bps, 
                deposit_limit, 
                borrow_limit, 
                borrow_fee_bps, 
                spread_fee_bps, 
                liquidation_fee_bps, 
                interest_rate_utils,
                interest_rate_aprs,
                test_scenario::ctx(scenario)
            );
        };
        
        test_scenario::next_tx(scenario, owner);
        {
            test_scenario::take_from_sender<ReserveConfig>(scenario)
        }
    }

    public fun create_clock(scenario: &mut Scenario, owner: address): Clock {
        test_scenario::next_tx(scenario, owner);
        {
            clock::create_for_testing(
                test_scenario::ctx(scenario)
            )
        }
    }

    public fun add_reserve<P, T: drop>(
        scenario: &mut Scenario, 
        owner: address,
        owner_cap: &LendingMarketOwnerCap<P>,
        price: u256,
        config: ReserveConfig,
        clock: &Clock,
    ) {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let metadata = test_scenario::take_from_sender<CoinMetadata<T>>(scenario);
            lending_market::add_reserve<P, T>(
                owner_cap,
                &mut lending_market,
                price,
                config,
                &metadata,
                clock,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender<CoinMetadata<T>>(scenario, metadata);
            test_scenario::return_shared(lending_market);
        };
    }

    public fun update_reserve_config<P, T>(
        scenario: &mut Scenario, 
        owner: address,
        owner_cap: &LendingMarketOwnerCap<P>,
        config: ReserveConfig,
    ) {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::update_reserve_config<P, T>(
                owner_cap,
                &mut lending_market,
                config,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };
    }

    public fun create_obligation<P>(scenario: &mut Scenario, user: address): ObligationOwnerCap<P> {
        test_scenario::next_tx(scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            
            lending_market::create_obligation<P>(
                &mut lending_market, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };
        
        test_scenario::next_tx(scenario, user);
        {
            test_scenario::take_from_address<ObligationOwnerCap<P>>(scenario, user)
        }
    }

    public fun deposit_reserve_liquidity<P, T>(
        scenario: &mut Scenario, 
        user: address, 
        clock: &Clock,
        tokens: Coin<T>
    ): Coin<CToken<P, T>> {
        test_scenario::next_tx(scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::deposit_liquidity_and_mint_ctokens<P, T>(
                &mut lending_market, 
                clock,
                tokens,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };
        
        test_scenario::next_tx(scenario, user);
        {
            test_scenario::take_from_sender<Coin<CToken<P, T>>>(scenario)
        }
    }

    public fun deposit_ctokens_into_obligation<P, T>(
        scenario: &mut Scenario, 
        user: address, 
        obligation_owner_cap: &ObligationOwnerCap<P>,
        tokens: Coin<CToken<P, T>>
    ) {
        test_scenario::next_tx(scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::deposit_ctokens_into_obligation<P, T>(
                &mut lending_market, 
                obligation_owner_cap,
                tokens,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };
    }

    public fun repay<P, T>(
        scenario: &mut Scenario, 
        user: address,
        obligation_id: ID,
        clock: &Clock,
        coins: Coin<T>
    ) {
        test_scenario::next_tx(scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::repay<P, T>(
                &mut lending_market, 
                obligation_id,
                clock,
                coins,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };
    }

    public fun borrow<P, T>(
        scenario: &mut Scenario, 
        user: address,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64
    ): Coin<T> {
        test_scenario::next_tx(scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::borrow<P, T>(
                &mut lending_market, 
                obligation_owner_cap,
                clock,
                amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };

        test_scenario::next_tx(scenario, user);
        {
            test_scenario::take_from_sender<Coin<T>>(scenario)
        }
    }

    public fun withdraw<P, T>(
        scenario: &mut Scenario, 
        user: address,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64
    ): Coin<T> {
        test_scenario::next_tx(scenario, user);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::withdraw<P, T>(
                &mut lending_market, 
                obligation_owner_cap,
                clock,
                amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };

        test_scenario::next_tx(scenario, user);
        {
            test_scenario::take_from_sender<Coin<T>>(scenario)
        }
    }

    public fun liquidate<P, Repay, Withdraw>(
        scenario: &mut Scenario,
        obligation_id: ID,
        liquidator: address,
        clock: &Clock,
        repay: Coin<Repay>
    ): Coin<Withdraw> {
        test_scenario::next_tx(scenario, liquidator);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            lending_market::liquidate<P, Repay, Withdraw>(
                &mut lending_market,
                obligation_id,
                clock,
                repay,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
        };

        test_scenario::next_tx(scenario, liquidator);
        {
            test_scenario::take_from_sender<Coin<Withdraw>>(scenario)
        }
    }

}