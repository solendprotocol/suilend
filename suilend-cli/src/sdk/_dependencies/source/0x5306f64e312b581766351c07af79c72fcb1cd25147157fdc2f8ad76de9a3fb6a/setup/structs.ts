import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { UID } from "../../0x2/object/structs";
import { bcs } from "@mysten/bcs";
import { SuiClient, SuiParsedData } from "@mysten/sui.js/client";

/* ============================== DeployerCap =============================== */

export function isDeployerCap(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::setup::DeployerCap"
  );
}

export interface DeployerCapFields {
  id: string;
}

export class DeployerCap {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::setup::DeployerCap";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("DeployerCap", {
      id: UID.bcs,
    });
  }

  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }

  static fromFields(fields: Record<string, any>): DeployerCap {
    return new DeployerCap(UID.fromFields(fields.id).id);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): DeployerCap {
    if (!isDeployerCap(item.type)) {
      throw new Error("not a DeployerCap type");
    }
    return new DeployerCap(item.fields.id.id);
  }

  static fromBcs(data: Uint8Array): DeployerCap {
    return DeployerCap.fromFields(DeployerCap.bcs.parse(data));
  }

  static fromSuiParsedData(content: SuiParsedData) {
    if (content.dataType !== "moveObject") {
      throw new Error("not an object");
    }
    if (!isDeployerCap(content.type)) {
      throw new Error(
        `object at ${(content.fields as any).id} is not a DeployerCap object`
      );
    }
    return DeployerCap.fromFieldsWithTypes(content);
  }

  static async fetch(client: SuiClient, id: string): Promise<DeployerCap> {
    const res = await client.getObject({ id, options: { showContent: true } });
    if (res.error) {
      throw new Error(
        `error fetching DeployerCap object at id ${id}: ${res.error.code}`
      );
    }
    if (
      res.data?.content?.dataType !== "moveObject" ||
      !isDeployerCap(res.data.content.type)
    ) {
      throw new Error(`object at id ${id} is not a DeployerCap object`);
    }
    return DeployerCap.fromFieldsWithTypes(res.data.content);
  }
}
