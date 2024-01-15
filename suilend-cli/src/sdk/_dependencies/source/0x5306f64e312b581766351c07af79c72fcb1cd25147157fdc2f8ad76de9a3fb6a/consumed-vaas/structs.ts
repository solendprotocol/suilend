import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Set } from "../set/structs";
import { bcs } from "@mysten/bcs";

/* ============================== ConsumedVAAs =============================== */

export function isConsumedVAAs(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::consumed_vaas::ConsumedVAAs"
  );
}

export interface ConsumedVAAsFields {
  hashes: Set;
}

export class ConsumedVAAs {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::consumed_vaas::ConsumedVAAs";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("ConsumedVAAs", {
      hashes: Set.bcs,
    });
  }

  readonly hashes: Set;

  constructor(hashes: Set) {
    this.hashes = hashes;
  }

  static fromFields(fields: Record<string, any>): ConsumedVAAs {
    return new ConsumedVAAs(
      Set.fromFields(
        `0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::bytes32::Bytes32`,
        fields.hashes
      )
    );
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): ConsumedVAAs {
    if (!isConsumedVAAs(item.type)) {
      throw new Error("not a ConsumedVAAs type");
    }
    return new ConsumedVAAs(Set.fromFieldsWithTypes(item.fields.hashes));
  }

  static fromBcs(data: Uint8Array): ConsumedVAAs {
    return ConsumedVAAs.fromFields(ConsumedVAAs.bcs.parse(data));
  }
}
