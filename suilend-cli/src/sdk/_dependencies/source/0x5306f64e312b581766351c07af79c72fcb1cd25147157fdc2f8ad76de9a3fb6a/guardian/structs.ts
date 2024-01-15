import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Bytes20 } from "../bytes20/structs";
import { bcs } from "@mysten/bcs";

/* ============================== Guardian =============================== */

export function isGuardian(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian::Guardian"
  );
}

export interface GuardianFields {
  pubkey: Bytes20;
}

export class Guardian {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian::Guardian";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Guardian", {
      pubkey: Bytes20.bcs,
    });
  }

  readonly pubkey: Bytes20;

  constructor(pubkey: Bytes20) {
    this.pubkey = pubkey;
  }

  static fromFields(fields: Record<string, any>): Guardian {
    return new Guardian(Bytes20.fromFields(fields.pubkey));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Guardian {
    if (!isGuardian(item.type)) {
      throw new Error("not a Guardian type");
    }
    return new Guardian(Bytes20.fromFieldsWithTypes(item.fields.pubkey));
  }

  static fromBcs(data: Uint8Array): Guardian {
    return Guardian.fromFields(Guardian.bcs.parse(data));
  }
}
