// example way to create a lending market
module suilend::launch {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use suilend::lending_market::{Self};

    struct LAUNCH has drop {}

    fun init(witness: LAUNCH, ctx: &mut TxContext) {
        let cap = lending_market::create_lending_market(witness, ctx);
        transfer::public_transfer(cap, tx_context::sender(ctx));
    }
    
}