import { Option } from "../../_dependencies/source/0x1/option/structs";
import {
  Balance,
  Supply,
} from "../../_dependencies/source/0x2/balance/structs";
import { UID } from "../../_dependencies/source/0x2/object/structs";
import { PriceIdentifier } from "../../_dependencies/source/0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e/price-identifier/structs";
import {
  Type,
} from "../../_framework/util";
import { Decimal } from "../decimal/structs";
import { bcs } from "@mysten/bcs";

/* ============================== Price =============================== */

export interface PriceFields {
  price: Decimal;
  lastUpdateTimestampMs: bigint;
}

export class Price {
  static readonly $typeName = "0x0::reserve::Price";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Price", {
      price: Decimal.bcs,
      last_update_timestamp_ms: bcs.u64(),
    });
  }

  readonly price: Decimal;
  readonly lastUpdateTimestampMs: bigint;

  constructor(fields: PriceFields) {
    this.price = fields.price;
    this.lastUpdateTimestampMs = fields.lastUpdateTimestampMs;
  }

  static fromFields(fields: Record<string, any>): Price {
    return new Price({
      price: Decimal.fromFields(fields.price),
      lastUpdateTimestampMs: BigInt(fields.last_update_timestamp_ms),
    });
  }

  static fromBcs(data: Uint8Array): Price {
    return Price.fromFields(Price.bcs.parse(data));
  }
}

/* ============================== CToken =============================== */

export interface CTokenFields {
  dummyField: boolean;
}

export class CToken {
  static readonly $typeName = "0x0::reserve::CToken";
  static readonly $numTypeParams = 2;

  static get bcs() {
    return bcs.struct("CToken", {
      dummy_field: bcs.bool(),
    });
  }

  readonly $typeArgs: [Type, Type];

  readonly dummyField: boolean;

  constructor(typeArgs: [Type, Type], dummyField: boolean) {
    this.$typeArgs = typeArgs;

    this.dummyField = dummyField;
  }

  static fromFields(
    typeArgs: [Type, Type],
    fields: Record<string, any>
  ): CToken {
    return new CToken(typeArgs, fields.dummy_field);
  }

  static fromBcs(typeArgs: [Type, Type], data: Uint8Array): CToken {
    return CToken.fromFields(typeArgs, CToken.bcs.parse(data));
  }
}

/* ============================== InterestRateModel =============================== */

export interface InterestRateModelFields {
  utils: Array<number>;
  aprs: Array<bigint>;
}

export class InterestRateModel {
  static readonly $typeName = "0x0::reserve::InterestRateModel";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("InterestRateModel", {
      utils: bcs.vector(bcs.u8()),
      aprs: bcs.vector(bcs.u64()),
    });
  }

  readonly utils: Array<number>;
  readonly aprs: Array<bigint>;

  constructor(fields: InterestRateModelFields) {
    this.utils = fields.utils;
    this.aprs = fields.aprs;
  }

  static fromFields(fields: Record<string, any>): InterestRateModel {
    return new InterestRateModel({
      utils: fields.utils.map((item: any) => item),
      aprs: fields.aprs.map((item: any) => BigInt(item)),
    });
  }

  static fromBcs(data: Uint8Array): InterestRateModel {
    return InterestRateModel.fromFields(InterestRateModel.bcs.parse(data));
  }
}

/* ============================== Reserve =============================== */

export interface ReserveFields {
  config: ReserveConfig | null;
  mintDecimals: number;
  priceIdentifier: PriceIdentifier;
  price: Decimal;
  priceLastUpdateTimestampS: bigint;
  availableAmount: bigint;
  ctokenSupply: bigint;
  borrowedAmount: Decimal;
  cumulativeBorrowRate: Decimal;
  interestLastUpdateTimestampS: bigint;
  feesAccumulated: Decimal;
}

export class Reserve {
  static readonly $typeName = "0x0::reserve::Reserve";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Reserve", {
      config: Option.bcs(ReserveConfig.bcs),
      mint_decimals: bcs.u8(),
      price_identifier: PriceIdentifier.bcs,
      price: Decimal.bcs,
      price_last_update_timestamp_s: bcs.u64(),
      available_amount: bcs.u64(),
      ctoken_supply: bcs.u64(),
      borrowed_amount: Decimal.bcs,
      cumulative_borrow_rate: Decimal.bcs,
      interest_last_update_timestamp_s: bcs.u64(),
      fees_accumulated: Decimal.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly config: ReserveConfig | null;
  readonly mintDecimals: number;
  readonly priceIdentifier: PriceIdentifier;
  readonly price: Decimal;
  readonly priceLastUpdateTimestampS: bigint;
  readonly availableAmount: bigint;
  readonly ctokenSupply: bigint;
  readonly borrowedAmount: Decimal;
  readonly cumulativeBorrowRate: Decimal;
  readonly interestLastUpdateTimestampS: bigint;
  readonly feesAccumulated: Decimal;

  constructor(typeArg: Type, fields: ReserveFields) {
    this.$typeArg = typeArg;

    this.config = fields.config;
    this.mintDecimals = fields.mintDecimals;
    this.priceIdentifier = fields.priceIdentifier;
    this.price = fields.price;
    this.priceLastUpdateTimestampS = fields.priceLastUpdateTimestampS;
    this.availableAmount = fields.availableAmount;
    this.ctokenSupply = fields.ctokenSupply;
    this.borrowedAmount = fields.borrowedAmount;
    this.cumulativeBorrowRate = fields.cumulativeBorrowRate;
    this.interestLastUpdateTimestampS = fields.interestLastUpdateTimestampS;
    this.feesAccumulated = fields.feesAccumulated;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Reserve {
    return new Reserve(typeArg, {
      config: null,
      // config:
      //   Option.fromFields<ReserveConfig>(
      //     `0x0::reserve::ReserveConfig`,
      //     fields.config
      //   ).vec[0] || null,
      mintDecimals: fields.mint_decimals,
      priceIdentifier: PriceIdentifier.fromFields(fields.price_identifier),
      price: Decimal.fromFields(fields.price),
      priceLastUpdateTimestampS: BigInt(fields.price_last_update_timestamp_s),
      availableAmount: BigInt(fields.available_amount),
      ctokenSupply: BigInt(fields.ctoken_supply),
      borrowedAmount: Decimal.fromFields(fields.borrowed_amount),
      cumulativeBorrowRate: Decimal.fromFields(fields.cumulative_borrow_rate),
      interestLastUpdateTimestampS: BigInt(
        fields.interest_last_update_timestamp_s
      ),
      feesAccumulated: Decimal.fromFields(fields.fees_accumulated),
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Reserve {
    return Reserve.fromFields(typeArg, Reserve.bcs.parse(data));
  }
}

/* ============================== ReserveConfig =============================== */

export interface ReserveConfigFields {
  id: string;
  openLtvPct: number;
  closeLtvPct: number;
  borrowWeightBps: bigint;
  depositLimit: bigint;
  borrowLimit: bigint;
  liquidationBonusPct: number;
  borrowFeeBps: bigint;
  spreadFeeBps: bigint;
  liquidationFeeBps: bigint;
  interestRate: InterestRateModel;
}

export class ReserveConfig {
  static readonly $typeName = "0x0::reserve::ReserveConfig";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("ReserveConfig", {
      id: UID.bcs,
      open_ltv_pct: bcs.u8(),
      close_ltv_pct: bcs.u8(),
      borrow_weight_bps: bcs.u64(),
      deposit_limit: bcs.u64(),
      borrow_limit: bcs.u64(),
      liquidation_bonus_pct: bcs.u8(),
      borrow_fee_bps: bcs.u64(),
      spread_fee_bps: bcs.u64(),
      liquidation_fee_bps: bcs.u64(),
      interest_rate: InterestRateModel.bcs,
    });
  }

  readonly id: string;
  readonly openLtvPct: number;
  readonly closeLtvPct: number;
  readonly borrowWeightBps: bigint;
  readonly depositLimit: bigint;
  readonly borrowLimit: bigint;
  readonly liquidationBonusPct: number;
  readonly borrowFeeBps: bigint;
  readonly spreadFeeBps: bigint;
  readonly liquidationFeeBps: bigint;
  readonly interestRate: InterestRateModel;

  constructor(fields: ReserveConfigFields) {
    this.id = fields.id;
    this.openLtvPct = fields.openLtvPct;
    this.closeLtvPct = fields.closeLtvPct;
    this.borrowWeightBps = fields.borrowWeightBps;
    this.depositLimit = fields.depositLimit;
    this.borrowLimit = fields.borrowLimit;
    this.liquidationBonusPct = fields.liquidationBonusPct;
    this.borrowFeeBps = fields.borrowFeeBps;
    this.spreadFeeBps = fields.spreadFeeBps;
    this.liquidationFeeBps = fields.liquidationFeeBps;
    this.interestRate = fields.interestRate;
  }

  static fromFields(fields: Record<string, any>): ReserveConfig {
    return new ReserveConfig({
      id: UID.fromFields(fields.id).id,
      openLtvPct: fields.open_ltv_pct,
      closeLtvPct: fields.close_ltv_pct,
      borrowWeightBps: BigInt(fields.borrow_weight_bps),
      depositLimit: BigInt(fields.deposit_limit),
      borrowLimit: BigInt(fields.borrow_limit),
      liquidationBonusPct: fields.liquidation_bonus_pct,
      borrowFeeBps: BigInt(fields.borrow_fee_bps),
      spreadFeeBps: BigInt(fields.spread_fee_bps),
      liquidationFeeBps: BigInt(fields.liquidation_fee_bps),
      interestRate: InterestRateModel.fromFields(fields.interest_rate),
    });
  }

  static fromBcs(data: Uint8Array): ReserveConfig {
    return ReserveConfig.fromFields(ReserveConfig.bcs.parse(data));
  }
}

/* ============================== ReserveTreasury =============================== */

export interface ReserveTreasuryFields {
  reserveId: bigint;
  availableAmount: Balance;
  ctokenSupply: Supply;
}

export class ReserveTreasury {
  static readonly $typeName = "0x0::reserve::ReserveTreasury";
  static readonly $numTypeParams = 2;

  static get bcs() {
    return bcs.struct("ReserveTreasury", {
      reserve_id: bcs.u64(),
      available_amount: Balance.bcs,
      ctoken_supply: Supply.bcs,
    });
  }

  readonly $typeArgs: [Type, Type];

  readonly reserveId: bigint;
  readonly availableAmount: Balance;
  readonly ctokenSupply: Supply;

  constructor(typeArgs: [Type, Type], fields: ReserveTreasuryFields) {
    this.$typeArgs = typeArgs;

    this.reserveId = fields.reserveId;
    this.availableAmount = fields.availableAmount;
    this.ctokenSupply = fields.ctokenSupply;
  }

  static fromFields(
    typeArgs: [Type, Type],
    fields: Record<string, any>
  ): ReserveTreasury {
    return new ReserveTreasury(typeArgs, {
      reserveId: BigInt(fields.reserve_id),
      availableAmount: Balance.fromFields(
        `${typeArgs[1]}`,
        fields.available_amount
      ),
      ctokenSupply: Supply.fromFields(
        `0x0::reserve::CToken<${typeArgs[0]}, ${typeArgs[1]}>`,
        fields.ctoken_supply
      ),
    });
  }

  static fromBcs(typeArgs: [Type, Type], data: Uint8Array): ReserveTreasury {
    return ReserveTreasury.fromFields(
      typeArgs,
      ReserveTreasury.bcs.parse(data)
    );
  }
}
