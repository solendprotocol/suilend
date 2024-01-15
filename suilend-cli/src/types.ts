import { bcs, BcsType, fromHEX, toHEX, fromB64, InferBcsType } from "@mysten/bcs";
import { JsonRpcClient, JsonRpcProvider } from "@mysten/sui.js";

export const ID = bcs.struct("ID", {
  bytes: bcs.bytes(32).transform({
    input: (val: string) => fromHEX(val),
    output: (val: Uint8Array) => toHEX(val),
  }),
});

export const UID = bcs.struct("UID", {
  id: ID,
});

export const ObligationOwnerCap = bcs.struct("ObligationOwnerCap", {
  id: UID,
  obligation_id: ID,
});

export const Decimal = bcs.struct("Decimal", {
  value: bcs.u256(),
});

export const Borrow = bcs.struct("Borrow", {
  reserve_id: bcs.u64(),
  borrowed_amount: Decimal,
  cumulative_borrow_rate: Decimal,
  market_value: Decimal,
});

export const Deposit = bcs.struct("Deposit", {
  reserve_id: bcs.u64(),
  deposited_ctoken_amount: bcs.u64(),
  market_value: Decimal,
});

export const Bag = bcs.struct("Bag", {
  id: UID,
  size: bcs.u64(),
});

export const Obligation = bcs.struct("Obligation", {
  id: UID,
  owner: bcs.bytes(32).transform({
    input: (val: string) => fromHEX(val),
    output: (val: Uint8Array) => toHEX(val),
  }),
  deposits: bcs.vector(Deposit),
  borrows: bcs.vector(Borrow),
  balances: Bag,
  deposited_value_usd: Decimal,
  allowed_borrow_value_usd: Decimal,
  unhealthy_borrow_value_usd: Decimal,
  unweighted_borrowed_value_usd: Decimal,
  weighted_borrowed_value_usd: Decimal,
});

export type ObligationType = InferBcsType<typeof Obligation>;

function Option<T>(T: BcsType<T>) {
  return bcs.struct(`Option<${T}>`, {
    vec: bcs.vector(T),
  });
}

 export const InterestRateModel = bcs.struct("InterestRateModel", {
  utils: bcs.vector(bcs.u8()),
  aprs: bcs.vector(bcs.u64()),
});

 export const ReserveConfig = bcs.struct("ReserveConfig", {
  id: UID,
  open_ltv_pct: bcs.u8(),
  close_ltv_pct: bcs.u8(),
  borrow_weight_bps: bcs.u64(),
  deposit_limit: bcs.u64(),
  borrow_limit: bcs.u64(),
  liquidation_bonus_pct: bcs.u8(),
  borrow_fee_bps: bcs.u64(),
  spread_fee_bps: bcs.u64(),
  liquidation_fee_bps: bcs.u64(),
  interest_rate: InterestRateModel,
});

 export const PriceIdentifier = bcs.struct("PriceIdentifier", {
  bytes: bcs.vector(bcs.u8()),
});

 export const Reserve = bcs.struct("Reserve", {
  config: Option(ReserveConfig),
  mint_decimals: bcs.u8(),
  price_identifier: PriceIdentifier,
  price: Decimal,
  price_last_update_timestamp_s: bcs.u64(),
  available_amount: bcs.u64(),
  ctoken_supply: bcs.u64(),
  borrowed_amount: Decimal,
  cumulative_borrow_rate: Decimal,
  interest_last_update_timestamp_s: bcs.u64(),
  fees_accumulated: Decimal,
});

 export const ObjectBag = bcs.struct("ObjectBag", {
  id: UID,
  size: bcs.u64(),
});

 export const LendingMarket = bcs.struct("LendingMarket", {
  id: UID,
  reserves: bcs.vector(Reserve),
  reserve_treasuries: Bag,
  obligations: ObjectBag,
});

export async function load<T>(client: JsonRpcProvider, type: BcsType<T>, id: string): Promise<T> {
  let data = await client.getObject({ id, options: { showBcs: true } });
  if (data.data?.bcs?.dataType !== "moveObject") {
    throw new Error("Error: invalid data type");
  }
  return type.parse(fromB64(data.data.bcs.bcsBytes));
}