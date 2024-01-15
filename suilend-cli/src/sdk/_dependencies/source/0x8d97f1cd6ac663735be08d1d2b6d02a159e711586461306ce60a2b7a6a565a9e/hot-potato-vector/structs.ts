import { initLoaderIfNeeded } from "../../../../_framework/init-source";
import { structClassLoaderSource } from "../../../../_framework/loader";
import {
  FieldsWithTypes,
  Type,
  compressSuiType,
  parseTypeName,
} from "../../../../_framework/util";
import { BcsType, bcs } from "@mysten/bcs";

/* ============================== HotPotatoVector =============================== */

export function isHotPotatoVector(type: Type): boolean {
  type = compressSuiType(type);
  return type.startsWith(
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::hot_potato_vector::HotPotatoVector<"
  );
}

export interface HotPotatoVectorFields<T> {
  contents: Array<T>;
}

export class HotPotatoVector<T> {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::hot_potato_vector::HotPotatoVector";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return <T extends BcsType<any>>(T: T) =>
      bcs.struct(`HotPotatoVector<${T.name}>`, {
        contents: bcs.vector(T),
      });
  }

  readonly $typeArg: Type;

  readonly contents: Array<T>;

  constructor(typeArg: Type, contents: Array<T>) {
    this.$typeArg = typeArg;

    this.contents = contents;
  }

  static fromFields<T>(
    typeArg: Type,
    fields: Record<string, any>
  ): HotPotatoVector<T> {
    initLoaderIfNeeded();

    return new HotPotatoVector(
      typeArg,
      fields.contents.map((item: any) =>
        structClassLoaderSource.fromFields(typeArg, item)
      )
    );
  }

  static fromFieldsWithTypes<T>(item: FieldsWithTypes): HotPotatoVector<T> {
    initLoaderIfNeeded();

    if (!isHotPotatoVector(item.type)) {
      throw new Error("not a HotPotatoVector type");
    }
    const { typeArgs } = parseTypeName(item.type);

    return new HotPotatoVector(
      typeArgs[0],
      item.fields.contents.map((item: any) =>
        structClassLoaderSource.fromFieldsWithTypes(typeArgs[0], item)
      )
    );
  }

  static fromBcs<T>(typeArg: Type, data: Uint8Array): HotPotatoVector<T> {
    initLoaderIfNeeded();

    const typeArgs = [typeArg];

    return HotPotatoVector.fromFields(
      typeArg,
      HotPotatoVector.bcs(
        structClassLoaderSource.getBcsType(typeArgs[0])
      ).parse(data)
    );
  }
}
