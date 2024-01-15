import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== UpdateFee =============================== */

export function isUpdateFee(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_update_fee::UpdateFee"
  );
}

export interface UpdateFeeFields {
  mantissa: bigint;
  exponent: bigint;
}

export class UpdateFee {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_update_fee::UpdateFee";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("UpdateFee", {
      mantissa: bcs.u64(),
      exponent: bcs.u64(),
    });
  }

  readonly mantissa: bigint;
  readonly exponent: bigint;

  constructor(fields: UpdateFeeFields) {
    this.mantissa = fields.mantissa;
    this.exponent = fields.exponent;
  }

  static fromFields(fields: Record<string, any>): UpdateFee {
    return new UpdateFee({
      mantissa: BigInt(fields.mantissa),
      exponent: BigInt(fields.exponent),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): UpdateFee {
    if (!isUpdateFee(item.type)) {
      throw new Error("not a UpdateFee type");
    }
    return new UpdateFee({
      mantissa: BigInt(item.fields.mantissa),
      exponent: BigInt(item.fields.exponent),
    });
  }

  static fromBcs(data: Uint8Array): UpdateFee {
    return UpdateFee.fromFields(UpdateFee.bcs.parse(data));
  }
}
