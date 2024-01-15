import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== PriceStatus =============================== */

export function isPriceStatus(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_status::PriceStatus"
  );
}

export interface PriceStatusFields {
  status: bigint;
}

export class PriceStatus {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_status::PriceStatus";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PriceStatus", {
      status: bcs.u64(),
    });
  }

  readonly status: bigint;

  constructor(status: bigint) {
    this.status = status;
  }

  static fromFields(fields: Record<string, any>): PriceStatus {
    return new PriceStatus(BigInt(fields.status));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PriceStatus {
    if (!isPriceStatus(item.type)) {
      throw new Error("not a PriceStatus type");
    }
    return new PriceStatus(BigInt(item.fields.status));
  }

  static fromBcs(data: Uint8Array): PriceStatus {
    return PriceStatus.fromFields(PriceStatus.bcs.parse(data));
  }
}
