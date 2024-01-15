import { initLoaderIfNeeded } from "../../../../_framework/init-source";
import { structClassLoaderSource } from "../../../../_framework/loader";
import {
  FieldsWithTypes,
  Type,
  compressSuiType,
  parseTypeName,
} from "../../../../_framework/util";
import { BcsType, bcs } from "@mysten/bcs";

/* ============================== Cursor =============================== */

export function isCursor(type: Type): boolean {
  type = compressSuiType(type);
  return type.startsWith(
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::cursor::Cursor<"
  );
}

export interface CursorFields<T> {
  data: Array<T>;
}

export class Cursor<T> {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::cursor::Cursor";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return <T extends BcsType<any>>(T: T) =>
      bcs.struct(`Cursor<${T.name}>`, {
        data: bcs.vector(T),
      });
  }

  readonly $typeArg: Type;

  readonly data: Array<T>;

  constructor(typeArg: Type, data: Array<T>) {
    this.$typeArg = typeArg;

    this.data = data;
  }

  static fromFields<T>(typeArg: Type, fields: Record<string, any>): Cursor<T> {
    initLoaderIfNeeded();

    return new Cursor(
      typeArg,
      fields.data.map((item: any) =>
        structClassLoaderSource.fromFields(typeArg, item)
      )
    );
  }

  static fromFieldsWithTypes<T>(item: FieldsWithTypes): Cursor<T> {
    initLoaderIfNeeded();

    if (!isCursor(item.type)) {
      throw new Error("not a Cursor type");
    }
    const { typeArgs } = parseTypeName(item.type);

    return new Cursor(
      typeArgs[0],
      item.fields.data.map((item: any) =>
        structClassLoaderSource.fromFieldsWithTypes(typeArgs[0], item)
      )
    );
  }

  static fromBcs<T>(typeArg: Type, data: Uint8Array): Cursor<T> {
    initLoaderIfNeeded();

    const typeArgs = [typeArg];

    return Cursor.fromFields(
      typeArg,
      Cursor.bcs(structClassLoaderSource.getBcsType(typeArgs[0])).parse(data)
    );
  }
}
