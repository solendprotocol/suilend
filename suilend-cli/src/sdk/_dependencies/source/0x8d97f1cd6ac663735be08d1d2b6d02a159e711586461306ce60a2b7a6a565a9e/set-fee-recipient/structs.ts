import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs, fromHEX, toHEX } from "@mysten/bcs";

/* ============================== PythFeeRecipient =============================== */

export function isPythFeeRecipient(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_fee_recipient::PythFeeRecipient"
  );
}

export interface PythFeeRecipientFields {
  recipient: string;
}

export class PythFeeRecipient {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_fee_recipient::PythFeeRecipient";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PythFeeRecipient", {
      recipient: bcs
        .bytes(32)
        .transform({
          input: (val: string) => fromHEX(val),
          output: (val: Uint8Array) => toHEX(val),
        }),
    });
  }

  readonly recipient: string;

  constructor(recipient: string) {
    this.recipient = recipient;
  }

  static fromFields(fields: Record<string, any>): PythFeeRecipient {
    return new PythFeeRecipient(`0x${fields.recipient}`);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PythFeeRecipient {
    if (!isPythFeeRecipient(item.type)) {
      throw new Error("not a PythFeeRecipient type");
    }
    return new PythFeeRecipient(`0x${item.fields.recipient}`);
  }

  static fromBcs(data: Uint8Array): PythFeeRecipient {
    return PythFeeRecipient.fromFields(PythFeeRecipient.bcs.parse(data));
  }
}
