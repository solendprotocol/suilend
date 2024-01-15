import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Bytes32 } from "../../0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a/bytes32/structs";
import { bcs } from "@mysten/bcs";

/* ============================== WormholeVAAVerificationReceipt =============================== */

export function isWormholeVAAVerificationReceipt(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::governance::WormholeVAAVerificationReceipt"
  );
}

export interface WormholeVAAVerificationReceiptFields {
  payload: Array<number>;
  digest: Bytes32;
  sequence: bigint;
}

export class WormholeVAAVerificationReceipt {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::governance::WormholeVAAVerificationReceipt";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("WormholeVAAVerificationReceipt", {
      payload: bcs.vector(bcs.u8()),
      digest: Bytes32.bcs,
      sequence: bcs.u64(),
    });
  }

  readonly payload: Array<number>;
  readonly digest: Bytes32;
  readonly sequence: bigint;

  constructor(fields: WormholeVAAVerificationReceiptFields) {
    this.payload = fields.payload;
    this.digest = fields.digest;
    this.sequence = fields.sequence;
  }

  static fromFields(
    fields: Record<string, any>
  ): WormholeVAAVerificationReceipt {
    return new WormholeVAAVerificationReceipt({
      payload: fields.payload.map((item: any) => item),
      digest: Bytes32.fromFields(fields.digest),
      sequence: BigInt(fields.sequence),
    });
  }

  static fromFieldsWithTypes(
    item: FieldsWithTypes
  ): WormholeVAAVerificationReceipt {
    if (!isWormholeVAAVerificationReceipt(item.type)) {
      throw new Error("not a WormholeVAAVerificationReceipt type");
    }
    return new WormholeVAAVerificationReceipt({
      payload: item.fields.payload.map((item: any) => item),
      digest: Bytes32.fromFieldsWithTypes(item.fields.digest),
      sequence: BigInt(item.fields.sequence),
    });
  }

  static fromBcs(data: Uint8Array): WormholeVAAVerificationReceipt {
    return WormholeVAAVerificationReceipt.fromFields(
      WormholeVAAVerificationReceipt.bcs.parse(data)
    );
  }
}
