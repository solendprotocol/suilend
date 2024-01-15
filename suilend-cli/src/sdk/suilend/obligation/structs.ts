import { JsonRpcProvider } from "@mysten/sui.js";
import { Bag } from "../../_dependencies/source/0x2/bag/structs";
import { UID } from "../../_dependencies/source/0x2/object/structs";
import {
  Type,
} from "../../_framework/util";
import { Decimal } from "../decimal/structs";
import { bcs, fromHEX, toHEX } from "@mysten/bcs";

/* ============================== Borrow =============================== */

export interface BorrowFields {
  reserveId: bigint;
  borrowedAmount: Decimal;
  cumulativeBorrowRate: Decimal;
  marketValue: Decimal;
}

export class Borrow {
  static readonly $typeName = "0x0::obligation::Borrow";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Borrow", {
      reserve_id: bcs.u64(),
      borrowed_amount: Decimal.bcs,
      cumulative_borrow_rate: Decimal.bcs,
      market_value: Decimal.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly reserveId: bigint;
  readonly borrowedAmount: Decimal;
  readonly cumulativeBorrowRate: Decimal;
  readonly marketValue: Decimal;

  constructor(typeArg: Type, fields: BorrowFields) {
    this.$typeArg = typeArg;

    this.reserveId = fields.reserveId;
    this.borrowedAmount = fields.borrowedAmount;
    this.cumulativeBorrowRate = fields.cumulativeBorrowRate;
    this.marketValue = fields.marketValue;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Borrow {
    return new Borrow(typeArg, {
      reserveId: BigInt(fields.reserve_id),
      borrowedAmount: Decimal.fromFields(fields.borrowed_amount),
      cumulativeBorrowRate: Decimal.fromFields(fields.cumulative_borrow_rate),
      marketValue: Decimal.fromFields(fields.market_value),
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Borrow {
    return Borrow.fromFields(typeArg, Borrow.bcs.parse(data));
  }
}

/* ============================== Deposit =============================== */

export interface DepositFields {
  reserveId: bigint;
  depositedCtokenAmount: bigint;
  marketValue: Decimal;
}

export class Deposit {
  static readonly $typeName = "0x0::obligation::Deposit";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Deposit", {
      reserve_id: bcs.u64(),
      deposited_ctoken_amount: bcs.u64(),
      market_value: Decimal.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly reserveId: bigint;
  readonly depositedCtokenAmount: bigint;
  readonly marketValue: Decimal;

  constructor(typeArg: Type, fields: DepositFields) {
    this.$typeArg = typeArg;

    this.reserveId = fields.reserveId;
    this.depositedCtokenAmount = fields.depositedCtokenAmount;
    this.marketValue = fields.marketValue;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Deposit {
    return new Deposit(typeArg, {
      reserveId: BigInt(fields.reserve_id),
      depositedCtokenAmount: BigInt(fields.deposited_ctoken_amount),
      marketValue: Decimal.fromFields(fields.market_value),
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Deposit {
    return Deposit.fromFields(typeArg, Deposit.bcs.parse(data));
  }
}

/* ============================== Key =============================== */

export interface KeyFields {
  dummyField: boolean;
}

export class Key {
  static readonly $typeName = "0x0::obligation::Key";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Key", {
      dummy_field: bcs.bool(),
    });
  }

  readonly $typeArg: Type;

  readonly dummyField: boolean;

  constructor(typeArg: Type, dummyField: boolean) {
    this.$typeArg = typeArg;

    this.dummyField = dummyField;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Key {
    return new Key(typeArg, fields.dummy_field);
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Key {
    return Key.fromFields(typeArg, Key.bcs.parse(data));
  }
}

/* ============================== Obligation =============================== */

export interface ObligationFields {
  id: string;
  owner: string;
  deposits: Array<Deposit>;
  borrows: Array<Borrow>;
  balances: Bag;
  depositedValueUsd: Decimal;
  allowedBorrowValueUsd: Decimal;
  unhealthyBorrowValueUsd: Decimal;
  unweightedBorrowedValueUsd: Decimal;
  weightedBorrowedValueUsd: Decimal;
}

export class Obligation {
  static readonly $typeName = "0x0::obligation::Obligation";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Obligation", {
      id: UID.bcs,
      owner: bcs
        .bytes(32)
        .transform({
          input: (val: string) => fromHEX(val),
          output: (val: Uint8Array) => toHEX(val),
        }),
      deposits: bcs.vector(Deposit.bcs),
      borrows: bcs.vector(Borrow.bcs),
      balances: Bag.bcs,
      deposited_value_usd: Decimal.bcs,
      allowed_borrow_value_usd: Decimal.bcs,
      unhealthy_borrow_value_usd: Decimal.bcs,
      unweighted_borrowed_value_usd: Decimal.bcs,
      weighted_borrowed_value_usd: Decimal.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly id: string;
  readonly owner: string;
  readonly deposits: Array<Deposit>;
  readonly borrows: Array<Borrow>;
  readonly balances: Bag;
  readonly depositedValueUsd: Decimal;
  readonly allowedBorrowValueUsd: Decimal;
  readonly unhealthyBorrowValueUsd: Decimal;
  readonly unweightedBorrowedValueUsd: Decimal;
  readonly weightedBorrowedValueUsd: Decimal;

  constructor(typeArg: Type, fields: ObligationFields) {
    this.$typeArg = typeArg;

    this.id = fields.id;
    this.owner = fields.owner;
    this.deposits = fields.deposits;
    this.borrows = fields.borrows;
    this.balances = fields.balances;
    this.depositedValueUsd = fields.depositedValueUsd;
    this.allowedBorrowValueUsd = fields.allowedBorrowValueUsd;
    this.unhealthyBorrowValueUsd = fields.unhealthyBorrowValueUsd;
    this.unweightedBorrowedValueUsd = fields.unweightedBorrowedValueUsd;
    this.weightedBorrowedValueUsd = fields.weightedBorrowedValueUsd;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Obligation {
    return new Obligation(typeArg, {
      id: UID.fromFields(fields.id).id,
      owner: `0x${fields.owner}`,
      deposits: fields.deposits.map((item: any) =>
        Deposit.fromFields(`${typeArg}`, item)
      ),
      borrows: fields.borrows.map((item: any) =>
        Borrow.fromFields(`${typeArg}`, item)
      ),
      balances: Bag.fromFields(fields.balances),
      depositedValueUsd: Decimal.fromFields(fields.deposited_value_usd),
      allowedBorrowValueUsd: Decimal.fromFields(
        fields.allowed_borrow_value_usd
      ),
      unhealthyBorrowValueUsd: Decimal.fromFields(
        fields.unhealthy_borrow_value_usd
      ),
      unweightedBorrowedValueUsd: Decimal.fromFields(
        fields.unweighted_borrowed_value_usd
      ),
      weightedBorrowedValueUsd: Decimal.fromFields(
        fields.weighted_borrowed_value_usd
      ),
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Obligation {
    return Obligation.fromFields(typeArg, Obligation.bcs.parse(data));
  }
}

/* ============================== RefreshedTicket =============================== */

export interface RefreshedTicketFields {
  dummyField: boolean;
}

export class RefreshedTicket {
  static readonly $typeName = "0x0::obligation::RefreshedTicket";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("RefreshedTicket", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): RefreshedTicket {
    return new RefreshedTicket(fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): RefreshedTicket {
    return RefreshedTicket.fromFields(RefreshedTicket.bcs.parse(data));
  }
}
