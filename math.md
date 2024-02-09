The goal of this page is to be a self-contained explanation of the big mathematical concepts involved in building a lending protocol.

# Reserve

For a given lending market, a reserve holds all deposits of a coin type for a given lending market. 
For example, the Suilend Main Market will have exactly 1 SUI reserve and 1 USDC reserve.

If a user deposits/repays SUI, the SUI reserve will increase in supply.

If a user borrows/withdraws SUI, the SUI reserve will decrease in supply.

## Reserve Utilization

$$U_{r} = B_{r} / T_r = B_r / (B_{r} + A_{r})$$

Where:
- $U_{r}$ is reserve utilization. $0 < U_{reserve} < 1$
- $B_r$ is the amount of tokens lent to borrowers from reserve $r$.
- $A_r$ is the amount of tokens available in reserve $r$. These are tokens that are have been deposited into the reserve but not borrowed yet.
- $T_r$ is the total supply of tokens in reserve $r$.

Example: Say I (ripleys) deposit 100 USDC into Suilend, and Soju (our bd guy) deposit 100 SUI and borrows 50 USDC. 

The reserve utilization on the USDC reserve is $50 / (50 + 50)$ = 50%.

## CTokens

When a user deposits SUI into Suilend, they will mint (ie get back) CSUI. This CSUI entitles the user to obtain their deposit from Suilend + additional interest. The interest is obtained by lending out the tokens to borrowers.

The CToken ratio denotes the exchange rate between the CToken and its underlying asset. Formally, the ctoken ratio is calculated by:
$$C_r = (B_r + A_r) / T_{C_r}$$

Where:
- $C_r$ is the ctoken ratio for reserve $r$
- $B_r$ is the amount of tokens lent to borrowers for reserve $r$ (including interest)
- $A_r$ is the amount of available tokens (ie not lent out) for reserve $r$
- $T_{C_r}$ is the total supply of ctokens in reserve $r$.


Notes:
- $C_r$ starts at 1 when the reserve is initialized, and grows over time. The CToken ratio never decreases.
- a user cannot always exchange their CSUI back to SUI. In a worst case scenario, all deposited SUI could be lent out, so the protocol won't have any left for redemption. However, in this scenario, the interest rates will skyrocket, incentivizing new depositors and also incentivizing borrowers to pay back their debts.
- the ctoken ratio captures the interest earned by a deposit.

# Obligations

An obligation tracks a user's deposits and borrows in a given lending market.

The USD value of a user's borrows can never exceed the USD value of a user's deposits. Otherwise, the protocol can pick up bad debt!

## Obligation statuses

### Healthy

An obligation O is healthy if:

$$ \sum_{r}^{M}{B(O, r)} < \sum_{r}^{M}{LTV_{open}(r) * D(O, r)}$$

Where:
- $M$ is the lending market
- $r$ is a reserve in $M$
- $B(O, r)$ is the USD value of obligation O's borrows from reserve $r$
- $D(O, r)$ is the USD value of obligation O's deposits from reserve $r$
- $LTV_{open}(r)$ is the open LTV for reserve $r$. ($0 <= LTV_{open}(r) < 1$)


### Unhealthy

An obligation O is unhealthy and eligible for liquidation if:

$$ \sum_{r}^{M}{B(O, r)} >= \sum_{r}^{M}{LTV_{close}(r) * D(O, r)}$$

Where:
- $LTV_{close}(r)$ is the close LTV for reserve $r$. ($0 <= LTV_{close}(r) < 1$)

### Underwater 

An obligation O is underwater if:

$$ \sum_{r}^{M}{B(O, r)} > \sum_{r}^{M}{D(O, r)}$$

In this situation, the protocol has picked up bad debt.

# Compounding debt and calculating interest rates

In Suilend, debt is compounded every second. 

Compounded debt is tracked per obligation _and_ per reserve. Debt needs to be tracked per reserve because it affects the ctoken ratio. Debt needs to be tracked per obligation because otherwise users won't pay back their debt!

This section is a bit complicated and only relevant if you want to understand the source code of the protocol.

## APR (Annual Percentage Rate)

An APR is a representation of the yearly interest paid on your debt, without accounting for compounding. 

In Suilend, the APR is a function of reserve utilization. The exact function is subject to change.

Note that reserve utilization only changes on a borrow or repay action.

## Compound debt per reserve

$B_r$ from prior formulas (total tokens borrowed in reserve $r$) provides us a convenient way to compound global debt on a per-reserve basis.

The formula below describes how to compound debt on a reserve:

$$B(t=1)_r = B(t=0)_r * (1 + APR(U_r) / Y_{seconds})^1$$

Where:
- $B(t)_r$ is the total amount of tokens borrowed in reserve $r$ at time $t$.
- $APR(U_r)$ is the APR for a given utilization value. 
- $Y_{seconds}$ is the number of seconds in a year.

Note that even if no additional users borrow tokens after $t=0$, due to compound interest, the borrowed amount will increase over time. 

## Compound debt per obligation

This is tricky to do efficiently since the APR can change every second and our borrowed amount can change on every borrow/repay action. Let's work through a simple example first.

Lets say the owner of obligation $O$ initially borrows $b$ tokens from reserve $r$ at $t=T_1$. 

What is the compounded debt at $t=T_2$?.

$$b\prod_{t=T_1 + 1}^{T_2}{(1 + APR_r(t)/365)}$$
Where:
- $B$ is the amount of tokens borrowed from reserve $r$ at $t=0$.
- $APR_r(t)$ is the variable APR for reserve $r$ at time $t$.

Lets define a new variable I that accumulates the products.

$$I_r(T) = \prod_{t=1}^{T}{(1 + APR_r(t)/365)}$$

Now, simplifying our first expression:

$$b * I_r(T_2) / I_r(T_1) $$

Note that the term $b / I_r(T_1)$ is effectively normalizing the debt to $t=0$. In other words, if you borrowed $b / I_r(T_1)$ tokens at t=0, your debt at $t=T_1$ would be $b$ after compounding interest.

Each obligation would "snapshot" the latest value of $I_r(t)$ after any action. This is equivalent to $I_r(T_1)$ in the expression above.

$I_r(t)$ can be tracked globally per reserve. This is equivalent to $I_r(T_2)$ in the expression above.

## Compounding debt invariant

At any time T and for any reserve, the following expression is true.

$$B_r = \sum_{o}^{M}{B_r(o) * I_r(T) / I_r(T'(o))}$$
Where:
- $B_r$ is the total amount of tokens borrowed in reserve $r$ at time $T$.
- $B_r(o)$ is the amount of tokens borrowed from reserve $r$ by obligation $O$.
- $I_r(T)$ is the latest cumulative borrow rate product for reserve $r$.
- $T'(o)$ is the last time the obligation's debt was compounded.

In other words, the global borrowed amount equals the sum of all borrowed tokens per obligation after compounding.

# Liquidations

The goal of liquidations is to force repay an unhealthy obligation's debt _before_ it goes underwater. Recall that an obligation O is unhealthy and eligible for liquidation if:

$$ \sum_{r}^{M}{B(O, r)} >= \sum_{r}^{M}{LTV_{close}(r) * D(O, r)}$$

Where:
- $M$ is the lending market
- $r$ is a reserve in $M$
- $B(O, r)$ is the USD value of obligation O's borrows from reserve $r$
- $D(O, r)$ is the USD value of obligation O's deposits from reserve $r$
- $LTV_{close}(r)$ is the close LTV for reserve $r$. ($0 <= LTV_{close}(r) < 1$)

Say the total value of a user's borrowed (deposited) amount is $B_{usd}$ ($D_{usd}$). The liquidator can repay $B_{usd} * CF$ of debt to receive $B_{usd} * CF * (1 + LB)$ worth of deposits.

Where:
- $CF$ is the close factor (see parameters section)
- $LB$ is the liquidation bonus (see parameters section)

Notes:
- when an obligation is unhealthy but not underwater, the LTV decreases after a liquidation. This is good. 
- the liquidation bonus (LB) is what makes the liquidation profitable for a liquidator.

# Parameters

## Open LTV (Loan-to-value)

Open LTV is a percentage that limits how much can be _initially_ borrowed against a deposit.

Open LTV is less than or equal to 1, and is defined _per_ reserve. This is because some tokens are more risky than others. For example, using USDC as collateral is much safer than using DOGE.

## Close LTV

Close LTV is a percentage that represents the maximum amount that can be borrowed against a deposit. 

For a given reserve, Close LTV > Open LTV.

## Close Factor (CF)

The Close Factor determines the percentage of an obligation's borrow that can be repaid on liquidation.

Bounds: $0 < CF <= 1$

## Liquidation Bonus (LB)

The liquidation bonus determines the bonus a liquidator gets when they liquidate an obligation. This bonus value is what makes a liquidation profitable for the liquidator.

Bounds: $0 <= LB < 1$

