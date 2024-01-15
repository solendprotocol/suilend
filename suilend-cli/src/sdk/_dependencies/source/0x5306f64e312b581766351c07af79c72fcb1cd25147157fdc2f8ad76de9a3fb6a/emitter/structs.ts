import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ID, UID } from "../../0x2/object/structs";
import { bcs } from "@mysten/bcs";
import { SuiClient, SuiParsedData } from "@mysten/sui.js/client";

/* ============================== EmitterCap =============================== */

export function isEmitterCap(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::emitter::EmitterCap"
  );
}

export interface EmitterCapFields {
  id: string;
  sequence: bigint;
}

export class EmitterCap {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::emitter::EmitterCap";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("EmitterCap", {
      id: UID.bcs,
      sequence: bcs.u64(),
    });
  }

  readonly id: string;
  readonly sequence: bigint;

  constructor(fields: EmitterCapFields) {
    this.id = fields.id;
    this.sequence = fields.sequence;
  }

  static fromFields(fields: Record<string, any>): EmitterCap {
    return new EmitterCap({
      id: UID.fromFields(fields.id).id,
      sequence: BigInt(fields.sequence),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): EmitterCap {
    if (!isEmitterCap(item.type)) {
      throw new Error("not a EmitterCap type");
    }
    return new EmitterCap({
      id: item.fields.id.id,
      sequence: BigInt(item.fields.sequence),
    });
  }

  static fromBcs(data: Uint8Array): EmitterCap {
    return EmitterCap.fromFields(EmitterCap.bcs.parse(data));
  }

  static fromSuiParsedData(content: SuiParsedData) {
    if (content.dataType !== "moveObject") {
      throw new Error("not an object");
    }
    if (!isEmitterCap(content.type)) {
      throw new Error(
        `object at ${(content.fields as any).id} is not a EmitterCap object`
      );
    }
    return EmitterCap.fromFieldsWithTypes(content);
  }

  static async fetch(client: SuiClient, id: string): Promise<EmitterCap> {
    const res = await client.getObject({ id, options: { showContent: true } });
    if (res.error) {
      throw new Error(
        `error fetching EmitterCap object at id ${id}: ${res.error.code}`
      );
    }
    if (
      res.data?.content?.dataType !== "moveObject" ||
      !isEmitterCap(res.data.content.type)
    ) {
      throw new Error(`object at id ${id} is not a EmitterCap object`);
    }
    return EmitterCap.fromFieldsWithTypes(res.data.content);
  }
}

/* ============================== EmitterCreated =============================== */

export function isEmitterCreated(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::emitter::EmitterCreated"
  );
}

export interface EmitterCreatedFields {
  emitterCap: string;
}

export class EmitterCreated {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::emitter::EmitterCreated";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("EmitterCreated", {
      emitter_cap: ID.bcs,
    });
  }

  readonly emitterCap: string;

  constructor(emitterCap: string) {
    this.emitterCap = emitterCap;
  }

  static fromFields(fields: Record<string, any>): EmitterCreated {
    return new EmitterCreated(ID.fromFields(fields.emitter_cap).bytes);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): EmitterCreated {
    if (!isEmitterCreated(item.type)) {
      throw new Error("not a EmitterCreated type");
    }
    return new EmitterCreated(item.fields.emitter_cap);
  }

  static fromBcs(data: Uint8Array): EmitterCreated {
    return EmitterCreated.fromFields(EmitterCreated.bcs.parse(data));
  }
}

/* ============================== EmitterDestroyed =============================== */

export function isEmitterDestroyed(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::emitter::EmitterDestroyed"
  );
}

export interface EmitterDestroyedFields {
  emitterCap: string;
}

export class EmitterDestroyed {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::emitter::EmitterDestroyed";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("EmitterDestroyed", {
      emitter_cap: ID.bcs,
    });
  }

  readonly emitterCap: string;

  constructor(emitterCap: string) {
    this.emitterCap = emitterCap;
  }

  static fromFields(fields: Record<string, any>): EmitterDestroyed {
    return new EmitterDestroyed(ID.fromFields(fields.emitter_cap).bytes);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): EmitterDestroyed {
    if (!isEmitterDestroyed(item.type)) {
      throw new Error("not a EmitterDestroyed type");
    }
    return new EmitterDestroyed(item.fields.emitter_cap);
  }

  static fromBcs(data: Uint8Array): EmitterDestroyed {
    return EmitterDestroyed.fromFields(EmitterDestroyed.bcs.parse(data));
  }
}
