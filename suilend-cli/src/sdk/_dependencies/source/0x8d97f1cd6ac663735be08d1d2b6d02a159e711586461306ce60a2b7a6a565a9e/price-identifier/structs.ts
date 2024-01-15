import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== PriceIdentifier =============================== */

export function isPriceIdentifier(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_identifier::PriceIdentifier"
  );
}

export interface PriceIdentifierFields {
  bytes: Array<number>;
}

export class PriceIdentifier {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_identifier::PriceIdentifier";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PriceIdentifier", {
      bytes: bcs.vector(bcs.u8()),
    });
  }

  readonly bytes: Array<number>;

  constructor(bytes: Array<number>) {
    this.bytes = bytes;
  }

  static fromFields(fields: Record<string, any>): PriceIdentifier {
    return new PriceIdentifier(fields.bytes.map((item: any) => item));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PriceIdentifier {
    if (!isPriceIdentifier(item.type)) {
      throw new Error("not a PriceIdentifier type");
    }
    return new PriceIdentifier(item.fields.bytes.map((item: any) => item));
  }

  static fromBcs(data: Uint8Array): PriceIdentifier {
    return PriceIdentifier.fromFields(PriceIdentifier.bcs.parse(data));
  }
}
