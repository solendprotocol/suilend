import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { I64 } from "../i64/structs";
import { bcs } from "@mysten/bcs";

/* ============================== Price =============================== */

export function isPrice(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price::Price"
  );
}

export interface PriceFields {
  price: I64;
  conf: bigint;
  expo: I64;
  timestamp: bigint;
}

export class Price {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price::Price";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Price", {
      price: I64.bcs,
      conf: bcs.u64(),
      expo: I64.bcs,
      timestamp: bcs.u64(),
    });
  }

  readonly price: I64;
  readonly conf: bigint;
  readonly expo: I64;
  readonly timestamp: bigint;

  constructor(fields: PriceFields) {
    this.price = fields.price;
    this.conf = fields.conf;
    this.expo = fields.expo;
    this.timestamp = fields.timestamp;
  }

  static fromFields(fields: Record<string, any>): Price {
    return new Price({
      price: I64.fromFields(fields.price),
      conf: BigInt(fields.conf),
      expo: I64.fromFields(fields.expo),
      timestamp: BigInt(fields.timestamp),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Price {
    if (!isPrice(item.type)) {
      throw new Error("not a Price type");
    }
    return new Price({
      price: I64.fromFieldsWithTypes(item.fields.price),
      conf: BigInt(item.fields.conf),
      expo: I64.fromFieldsWithTypes(item.fields.expo),
      timestamp: BigInt(item.fields.timestamp),
    });
  }

  static fromBcs(data: Uint8Array): Price {
    return Price.fromFields(Price.bcs.parse(data));
  }
}
