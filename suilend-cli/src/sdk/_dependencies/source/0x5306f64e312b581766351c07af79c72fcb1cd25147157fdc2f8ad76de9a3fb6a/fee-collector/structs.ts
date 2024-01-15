import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Balance } from "../../0x2/balance/structs";
import { bcs } from "@mysten/bcs";

/* ============================== FeeCollector =============================== */

export function isFeeCollector(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::fee_collector::FeeCollector"
  );
}

export interface FeeCollectorFields {
  feeAmount: bigint;
  balance: Balance;
}

export class FeeCollector {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::fee_collector::FeeCollector";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("FeeCollector", {
      fee_amount: bcs.u64(),
      balance: Balance.bcs,
    });
  }

  readonly feeAmount: bigint;
  readonly balance: Balance;

  constructor(fields: FeeCollectorFields) {
    this.feeAmount = fields.feeAmount;
    this.balance = fields.balance;
  }

  static fromFields(fields: Record<string, any>): FeeCollector {
    return new FeeCollector({
      feeAmount: BigInt(fields.fee_amount),
      balance: Balance.fromFields(`0x2::sui::SUI`, fields.balance),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): FeeCollector {
    if (!isFeeCollector(item.type)) {
      throw new Error("not a FeeCollector type");
    }
    return new FeeCollector({
      feeAmount: BigInt(item.fields.fee_amount),
      balance: new Balance(`0x2::sui::SUI`, BigInt(item.fields.balance)),
    });
  }

  static fromBcs(data: Uint8Array): FeeCollector {
    return FeeCollector.fromFields(FeeCollector.bcs.parse(data));
  }
}
