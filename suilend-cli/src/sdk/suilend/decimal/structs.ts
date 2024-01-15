import { Type } from "../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== Decimal =============================== */

export interface DecimalFields {
  value: bigint;
}

export class Decimal {
  static readonly $typeName = "0x0::decimal::Decimal";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Decimal", {
      value: bcs.u256(),
    });
  }

  readonly value: bigint;

  constructor(value: bigint) {
    this.value = value;
  }

  static fromFields(fields: Record<string, any>): Decimal {
    return new Decimal(BigInt(fields.value));
  }

  static fromBcs(data: Uint8Array): Decimal {
    return Decimal.fromFields(Decimal.bcs.parse(data));
  }
}
