# Suilend
Lending protocol on the Sui Blockchain

# Overview of terminology

A LendingMarket object holds many Reserves and Obligations.

An Obligation is a representations of a user's deposits and borrows. An obligation has exactly one lending market. 

There is 1 Reserve per token type (e.g a SUI Reserve, a SOL Reserve, a USDC Reserve). 
A user can supply assets to the reserve to earn interest, and/or borrow assets from a reserve and pay interest.
When a user deposits assets into a reserve, they will receive CTokens. 
The CToken represents the user's ownership of their deposit, and entitles the user to earn interest on their deposit.
