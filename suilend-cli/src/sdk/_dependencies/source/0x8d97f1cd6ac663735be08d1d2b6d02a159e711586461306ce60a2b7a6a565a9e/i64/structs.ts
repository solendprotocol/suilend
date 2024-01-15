import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== I64 =============================== */

export function isI64(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::i64::I64"
  );
}

export interface I64Fields {
  negative: boolean;
  magnitude: bigint;
}

export class I64 {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::i64::I64";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("I64", {
      negative: bcs.bool(),
      magnitude: bcs.u64(),
    });
  }

  readonly negative: boolean;
  readonly magnitude: bigint;

  constructor(fields: I64Fields) {
    this.negative = fields.negative;
    this.magnitude = fields.magnitude;
  }

  static fromFields(fields: Record<string, any>): I64 {
    return new I64({
      negative: fields.negative,
      magnitude: BigInt(fields.magnitude),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): I64 {
    if (!isI64(item.type)) {
      throw new Error("not a I64 type");
    }
    return new I64({
      negative: item.fields.negative,
      magnitude: BigInt(item.fields.magnitude),
    });
  }

  static fromBcs(data: Uint8Array): I64 {
    return I64.fromFields(I64.bcs.parse(data));
  }
}
