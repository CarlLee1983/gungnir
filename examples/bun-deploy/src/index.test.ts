import { test, expect } from "bun:test";
import { greeting } from "./index";

test("greeting returns hello, NAME", () => {
  expect(greeting("gungnir")).toBe("hello, gungnir");
});
