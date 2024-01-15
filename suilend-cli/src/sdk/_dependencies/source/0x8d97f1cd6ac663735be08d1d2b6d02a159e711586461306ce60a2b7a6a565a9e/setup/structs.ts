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
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::setup::DeployerCap"
  );
}

export interface DeployerCapFields {
  id: string;
}

export class DeployerCap {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::setup::DeployerCap";
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
