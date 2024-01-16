import {
  Type,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== Balance =============================== */

export interface BalanceFields {
  value: bigint;
}

export class Balance {
  static readonly $typeName = "0x2::balance::Balance";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Balance", {
      value: bcs.u64(),
    });
  }

  readonly $typeArg: Type;

  readonly value: bigint;

  constructor(typeArg: Type, value: bigint) {
    this.$typeArg = typeArg;

    this.value = value;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Balance {
    return new Balance(typeArg, BigInt(fields.value));
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Balance {
    return Balance.fromFields(typeArg, Balance.bcs.parse(data));
  }
}

/* ============================== Supply =============================== */

export interface SupplyFields {
  value: bigint;
}

export class Supply {
  static readonly $typeName = "0x2::balance::Supply";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Supply", {
      value: bcs.u64(),
    });
  }

  readonly $typeArg: Type;

  readonly value: bigint;

  constructor(typeArg: Type, value: bigint) {
    this.$typeArg = typeArg;

    this.value = value;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Supply {
    return new Supply(typeArg, BigInt(fields.value));
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Supply {
    return Supply.fromFields(typeArg, Supply.bcs.parse(data));
  }
}
