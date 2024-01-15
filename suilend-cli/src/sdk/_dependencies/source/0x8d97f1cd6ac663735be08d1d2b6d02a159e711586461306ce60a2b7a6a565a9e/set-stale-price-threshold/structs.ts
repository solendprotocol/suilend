import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== StalePriceThreshold =============================== */

export function isStalePriceThreshold(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_stale_price_threshold::StalePriceThreshold"
  );
}

export interface StalePriceThresholdFields {
  threshold: bigint;
}

export class StalePriceThreshold {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_stale_price_threshold::StalePriceThreshold";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("StalePriceThreshold", {
      threshold: bcs.u64(),
    });
  }

  readonly threshold: bigint;

  constructor(threshold: bigint) {
    this.threshold = threshold;
  }

  static fromFields(fields: Record<string, any>): StalePriceThreshold {
    return new StalePriceThreshold(BigInt(fields.threshold));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): StalePriceThreshold {
    if (!isStalePriceThreshold(item.type)) {
      throw new Error("not a StalePriceThreshold type");
    }
    return new StalePriceThreshold(BigInt(item.fields.threshold));
  }

  static fromBcs(data: Uint8Array): StalePriceThreshold {
    return StalePriceThreshold.fromFields(StalePriceThreshold.bcs.parse(data));
  }
}
