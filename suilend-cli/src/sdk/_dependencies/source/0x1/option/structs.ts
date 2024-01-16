import { BcsType, bcs } from "@mysten/bcs";

/* ============================== Option =============================== */

export interface OptionFields<Element> {
  vec: Array<Element>;
}

export class Option<Element> {
  static readonly $typeName = "0x1::option::Option";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return <Element extends BcsType<any>>(Element: Element) =>
      bcs.struct(`Option<${Element.name}>`, {
        vec: bcs.vector(Element),
      });
  }
}
