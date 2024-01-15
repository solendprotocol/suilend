import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ID } from "../../0x2/object/structs";
import { bcs } from "@mysten/bcs";

/* ============================== MigrateComplete =============================== */

export function isMigrateComplete(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::migrate::MigrateComplete"
  );
}

export interface MigrateCompleteFields {
  package: string;
}

export class MigrateComplete {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::migrate::MigrateComplete";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("MigrateComplete", {
      package: ID.bcs,
    });
  }

  readonly package: string;

  constructor(package_: string) {
    this.package = package_;
  }

  static fromFields(fields: Record<string, any>): MigrateComplete {
    return new MigrateComplete(ID.fromFields(fields.package).bytes);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): MigrateComplete {
    if (!isMigrateComplete(item.type)) {
      throw new Error("not a MigrateComplete type");
    }
    return new MigrateComplete(item.fields.package);
  }

  static fromBcs(data: Uint8Array): MigrateComplete {
    return MigrateComplete.fromFields(MigrateComplete.bcs.parse(data));
  }
}
